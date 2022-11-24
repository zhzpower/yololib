/*
 yololib
 Inject dylibs into existing Mach-O binaries
 
 
 DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
 Version 2, December 2004
 
 Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>
 
 Everyone is permitted to copy and distribute verbatim or modified
 copies of this license document, and changing it is allowed as long
 as the name is changed.
 
 DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
 TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
 
 0. You just DO WHAT THE FUCK YOU WANT TO.
 
 1. 读取macho文件到内存中
 2. 新增cmd
    2.1 ncmds 增加1
    2.2 sizeofcmds 增加插入的dylib的size
    2.3 填充dylib_command数据
 3. 写入macho中
 */

#include <stdio.h>
#include <string.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#import <Foundation/Foundation.h>


NSString* DYLIB_PATH;

#define DYLIB_CURRENT_VER 0x10000
#define DYLIB_COMPATIBILITY_VERSION 0x10000

#define ARMV7 9
#define ARMV6 6

unsigned long b_round(
                      unsigned long v,
                      unsigned long r) {
    r--;
    v += r;
    v &= ~(long)r;
    return(v);
}

void inject_dylib(FILE* newFile, uint32_t top) {
    fseek(newFile, top, SEEK_SET);
    struct mach_header mach;
    
    fread(&mach, sizeof(struct mach_header), 1, newFile);
    
    NSData* data = [DYLIB_PATH dataUsingEncoding:NSUTF8StringEncoding];
    
    uint32_t dylib_size = (uint32_t)[data length] + sizeof(struct dylib_command);
    dylib_size += sizeof(long) - (dylib_size % sizeof(long)); // load commands like to be aligned by long
    
    mach.ncmds += 1;
    uint32_t sizeofcmds = mach.sizeofcmds;
    mach.sizeofcmds += dylib_size;
    
    fseek(newFile, -sizeof(struct mach_header), SEEK_CUR);
    fwrite(&mach, sizeof(struct mach_header), 1, newFile);
    NSLog(@"Patching mach_header..\n");
    
    fseek(newFile, sizeofcmds, SEEK_CUR);
    
    struct dylib_command dyld;
    fread(&dyld, sizeof(struct dylib_command), 1, newFile);
    
    NSLog(@"Attaching dylib..\n\n");
    
    dyld.cmd = LC_LOAD_DYLIB;
    dyld.cmdsize = dylib_size;
    dyld.dylib.compatibility_version = DYLIB_COMPATIBILITY_VERSION;
    dyld.dylib.current_version = DYLIB_CURRENT_VER;
    dyld.dylib.timestamp = 2;
    dyld.dylib.name.offset = sizeof(struct dylib_command);
    fseek(newFile, -sizeof(struct dylib_command), SEEK_CUR);
    
    fwrite(&dyld, sizeof(struct dylib_command), 1, newFile);
    
    fwrite([data bytes], [data length], 1, newFile);
    
}

void inject_dylib_64(FILE* newFile, uint32_t top) {
    @autoreleasepool {
        // 设置stream文件开始的位置: SEEK_SET 文件的开头
        fseek(newFile, top, SEEK_SET);
        struct mach_header_64 mach;
        fread(&mach, sizeof(struct mach_header_64), 1, newFile);
        
        NSData* data = [DYLIB_PATH dataUsingEncoding:NSUTF8StringEncoding];
        unsigned long dylib_size = sizeof(struct dylib_command) + b_round(strlen([DYLIB_PATH UTF8String]) + 1, 8);
        //round(strlen([DYLIB_PATH UTF8String]) + 1, sizeof(long));
        NSLog(@"dylib size wow %lu", dylib_size);
        /*uint32_t dylib_size2 = (uint32_t)[data length] + sizeof(struct dylib_command);
         dylib_size2 += sizeof(long) - (dylib_size % sizeof(long)); // load commands like to be aligned by long
         
         NSLog(@"dylib size2 wow %u", dylib_size2);
         NSLog(@"dylib size2 wow %u", CFSwapInt32(dylib_size2));*/
        // number of load commands
        NSLog(@"mach.ncmds %u", mach.ncmds);
        // 增加1条load commands
        mach.ncmds += 0x1;
        NSLog(@"mach.ncmds %u", mach.ncmds);
        // 增加cmds的大小
        uint32_t sizeofcmds = mach.sizeofcmds;
        mach.sizeofcmds += (dylib_size);
        
        fseek(newFile, -sizeof(struct mach_header_64), SEEK_CUR);
        fwrite(&mach, sizeof(struct mach_header_64), 1, newFile);
        NSLog(@"Patching mach_header..\n");
        
        fseek(newFile, sizeofcmds, SEEK_CUR);
        
        // 填充新增的cmd 数据
        struct dylib_command dyld;
        fread(&dyld, sizeof(struct dylib_command), 1, newFile);
        
        NSLog(@"Attaching dylib..\n\n");
        
        dyld.cmd = LC_LOAD_DYLIB;
        dyld.cmdsize = (uint32_t) dylib_size;
        dyld.dylib.compatibility_version = DYLIB_COMPATIBILITY_VERSION;
        dyld.dylib.current_version = DYLIB_CURRENT_VER;
        dyld.dylib.timestamp = 2;
        dyld.dylib.name.offset = sizeof(struct dylib_command);
        fseek(newFile, -sizeof(struct dylib_command), SEEK_CUR);
        
        fwrite(&dyld, sizeof(struct dylib_command), 1, newFile);
        fwrite([data bytes], [data length], 1, newFile);
        NSLog(@"size %lu", sizeof(struct dylib_command) + [data length]);
    }
}


void inject_file(NSString* file, NSString* _dylib) {
    char buffer[4096], binary[4096], dylib[4096];
        
    strlcpy(binary, [file UTF8String], sizeof(binary));
    strlcpy(dylib, [DYLIB_PATH UTF8String], sizeof(dylib));
    
    // 使用给定的模式 mode 打开 filename 所指向的文件。文件顺利打开后，指向该流的文件指针就会被返回
    FILE *binaryFile = fopen(binary, "r+");
    if (binaryFile == NULL) {
        printf("open file fail!!!!");
        exit(1);
    }
    printf("Reading binary: %s\n\n", binary);
    //读取输入流binaryFile到 buffer中
    fread(&buffer, sizeof(buffer), 1, binaryFile);
    
/*
 如果是多架构fat文件，文件的头部定义为:
 struct fat_header {
     uint32_t    magic;        / FAT_MAGIC 或 FAT_MAGIC_64,加载器会通过这个符号来判断这是什么文件，通用二进制的 magic 为 0xcafebabe /
     uint32_t    nfat_arch;    / 结构体实例的个数 /
 };
 struct fat_arch {
     cpu_type_t    cputype;    / cpu specifier (int) /
     cpu_subtype_t    cpusubtype;    / machine specifier (int) /
     uint32_t    offset;        / file offset to this object file /
     uint32_t    size;        / size of this object file /
     uint32_t    align;        / alignment as a power of 2 /
 };
*/
/*
 如果是单架构macho文件，文件的头部定义为:
  * The 32-bit mach header appears at the very beginning of the object file for
  * 32-bit architectures.
 struct mach_header {
     uint32_t    magic;        / mach magic number identifier /
     cpu_type_t    cputype;    / cpu specifier /
     cpu_subtype_t    cpusubtype;    / machine specifier /
     uint32_t    filetype;    / type of file /
     uint32_t    ncmds;        / number of load commands /
     uint32_t    sizeofcmds;    / the size of all the load commands /
     uint32_t    flags;        / flags /
 };

 * Constant for the magic field of the mach_header (32-bit architectures) *
 #define    MH_MAGIC    0xfeedface    * the mach magic number *
 #define MH_CIGAM    0xcefaedfe    * NXSwapInt(MH_MAGIC) *

 *
  * The 64-bit mach header appears at the very beginning of object files for
  * 64-bit architectures.
  *
 struct mach_header_64 {
     uint32_t    magic;        * mach magic number identifier *
     cpu_type_t    cputype;    * cpu specifier *
     cpu_subtype_t    cpusubtype;    * machine specifier *
     uint32_t    filetype;    * type of file *
     uint32_t    ncmds;        * number of load commands *
     uint32_t    sizeofcmds;    * the size of all the load commands *
     uint32_t    flags;        * flags *
     uint32_t    reserved;    * reserved *
 };
 */
    struct fat_header* fh = (struct fat_header*) (buffer);
    
    switch (fh->magic) {
            // 多架构
        case FAT_CIGAM:
        case FAT_MAGIC: {
            struct fat_arch* arch = (struct fat_arch*) &fh[1];
            NSLog(@"FAT binary!\n");
            int i;
            for (i = 0; i < CFSwapInt32(fh->nfat_arch); i++) {
                NSLog(@"Injecting to arch %i\n", CFSwapInt32(arch->cpusubtype));
                if (CFSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                    NSLog(@"64bit arch wow");
                    inject_dylib_64(binaryFile, CFSwapInt32(arch->offset));
                }
                else {
                    inject_dylib(binaryFile, CFSwapInt32(arch->offset));
                }
                arch++;
            }
            break;
        }
            // 单架构
        case MH_CIGAM_64:
        case MH_MAGIC_64: {
            NSLog(@"Thin 64bit binary!\n");
            inject_dylib_64(binaryFile, 0);
            break;
        }
        case MH_CIGAM:
        case MH_MAGIC: {
            NSLog(@"Thin 32bit binary!\n");
            inject_dylib_64(binaryFile, 0);
            break;
        }
        default: {
            printf("Error: Unknown architecture detected");
            exit(1);
        }
    }
    
    NSLog(@"complete!");
    fclose(binaryFile);
}

int main(int argc, const char * argv[]) {
    const char *target_macho_path = argv[1];
    if (target_macho_path == NULL) {
        NSLog(@"target binary must be set!!!!\nfail!!!");
        return -1;
    }
    const char *target_framework_path = argv[2];
    if (target_framework_path == NULL) {
        NSLog(@"target framework must be set!!!!\nfail!!!");
        return -1;
    }
    NSString* binary = [NSString stringWithUTF8String:target_macho_path];
    NSString* dylib = [NSString stringWithUTF8String:target_framework_path];
    DYLIB_PATH = [NSString stringWithFormat:@"@executable_path/%@", dylib];
    NSLog(@"dylib path %@", DYLIB_PATH);
    
    inject_file(binary, DYLIB_PATH);
    
    return 0;
}

