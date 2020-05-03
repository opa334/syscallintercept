#include "substrate.h"

#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/reloc.h>

#include <dlfcn.h>

const char* dylibPath;
vm_address_t interceptAddr;

uint64_t read64(mach_port_name_t target, vm_address_t address);
uint32_t read32(mach_port_name_t target, vm_address_t address);
#ifdef __LP64__
void parseMachHeaderCommands(const mach_header_64* mh, intptr_t slide);
#else
void parseMachHeaderCommands(const mach_header* mh, intptr_t slide);
#endif
void parseMemory(vm_address_t addr, vm_offset_t length);
void syscallIntercept();

uint64_t read64(mach_port_name_t target, vm_address_t address)
{
	kern_return_t r;
	vm_offset_t data;
	mach_msg_type_number_t dataCnt;

	r = vm_read(target, address, sizeof(uint64_t), &data, &dataCnt);

	if(r == KERN_SUCCESS)
	{
		return *(uint64_t*)data;
	}
	else
	{
		return 0;
	}
}

uint32_t read32(mach_port_name_t target, vm_address_t address)
{
	kern_return_t r;
	vm_offset_t data;
	mach_msg_type_number_t dataCnt;

	r = vm_read(target, address, sizeof(uint32_t), &data, &dataCnt);

	if(r == KERN_SUCCESS)
	{
		return *(uint32_t*)data;
	}
	else
	{
		return 0;
	}
}

#ifdef __LP64__
void parseMachHeaderCommands(const mach_header_64* mh, intptr_t slide)
#else
void parseMachHeaderCommands(const mach_header* mh, intptr_t slide)
#endif
{
  #ifdef __LP64__
	const segment_command_64* cmd;
	const section_64* sect;
  #else
	const segment_command* cmd;
	const section* sect;
  #endif

	NSLog(@"mh = %llX", (unsigned long long)mh);

	uintptr_t addr = (uintptr_t)(mh + 1);

	NSLog(@"addr = %llX, size = %llX", (unsigned long long)addr, (unsigned long long)sizeof(mh));

	uintptr_t endAddr = addr + mh->sizeofcmds;

	for(int ci = 0; ci < mh->ncmds && addr <= endAddr; ci++)
	{
		cmd = (typeof(cmd))addr;

		addr = addr + cmd->cmdsize;

		if(cmd->cmd != LC_SEGMENT_64 || strcmp(cmd->segname, "__TEXT"))	//We only care about __TEXT segments
		{
			continue;
		}

		parseMemory(cmd->vmaddr + slide, cmd->vmsize);

		NSLog(@"- segname = %s, cmd = %lX, vmaddr = %llX, vmsize = %llX, nsects = %lu, cmdsize = %lu", cmd->segname, (unsigned long)cmd->cmd, (unsigned long long)cmd->vmaddr, (unsigned long long)cmd->vmsize, (unsigned long)cmd->nsects, (unsigned long)cmd->cmdsize);

		if(cmd->nsects > 0)
		{
			sect = (typeof(sect))((uintptr_t)cmd + sizeof(cmd));
			for(unsigned long si = 0; si < cmd->nsects; si++)
			{
				sect = sect + 1;

				//addr = addr + sizeof(sect);

				NSLog(@"-- sectname %s, addr = %llX, offset = %llX, size = %llX", sect->sectname, (unsigned long long)sect->addr, (unsigned long long)sect->offset, (unsigned long long)sect->size);
			}
		}
	}
}

uint32_t b(vm_address_t origin, vm_address_t target)
{
	int32_t offset = (target - origin) / 4;

	NSLog(@"b");

	NSLog(@"origin = %llX | target = %llX", (unsigned long long)origin, (unsigned long long)target);

	NSLog(@"offset = %i", offset);

	if(offset < 0)
	{
		if((offset & 0b1111110000000000000000000000000) != 0b1111110000000000000000000000000)
		{
			NSLog(@"ERROR: OFFSET TOO SMALL");
		}
	}
	else
	{
		if((offset & 0b1111110000000000000000000000000) != 0)
		{
			NSLog(@"ERROR: OFFSET TOO BIG");
		}
	}

	uint32_t bl = 0b00010100000000000000000000000000 | (offset & 0b00000011111111111111111111111111);

	return bl;
}

uint32_t bl(vm_address_t origin, vm_address_t target)
{
	int32_t offset = (target - origin) / 4;

	NSLog(@"bl");

	NSLog(@"origin = %llX | target = %llX", (unsigned long long)origin, (unsigned long long)target);

	NSLog(@"offset = %i", offset);

	if(offset < 0)
	{
		if((offset & 0b1111110000000000000000000000000) != 0b1111110000000000000000000000000)
		{
			NSLog(@"ERROR: OFFSET TOO SMALL");
		}
	}
	else
	{
		if((offset & 0b1111110000000000000000000000000) != 0)
		{
			NSLog(@"ERROR: OFFSET TOO BIG");
		}
	}

	uint32_t bl = 0b10010100000000000000000000000000 | (offset & 0b00000011111111111111111111111111);

	return bl;
}

/*void volatile test()
   {
 #ifdef __LP64__
        __asm("mov x30, x18");	//FE 03 12 AA
        __asm("mov x18, x30");	//F2 03 1E AA
 #endif
   }*/

vm_address_t create_trampoline(vm_address_t origin)
{
	vm_address_t addr = origin;
	vm_address_t ret = origin + 4;

	kern_return_t kret = vm_allocate(mach_task_self(), &addr, 16, true);	//Allocate next available space

	if(kret != KERN_SUCCESS)
	{
		NSLog(@"ERROR ALLOCATING");
		return 0;
	}

	uint32_t saveX30 = CFSwapInt32(0xFE0312AA);	//mov x30, x18
	uint32_t interceptCall = bl(addr + 4, interceptAddr);
	uint32_t loadX30 = CFSwapInt32(0xF2031EAA);	//mov x18, x30
	uint32_t jumpBack = b(addr + 12, ret);

	uint32_t trampoline[4] = { saveX30, interceptCall, loadX30, jumpBack };

	//kret = vm_write(mach_task_self(), addr, (vm_offset_t)trampoline, sizeof(trampoline));
	MSHookMemory((void*)addr, (const void*)trampoline, sizeof(trampoline));	//Needed so the code signature is not broken

	kern_return_t kret2 = vm_protect(mach_task_self(), addr, 16, true, VM_PROT_READ | VM_PROT_EXECUTE);	//set max protection
	kret = vm_protect(mach_task_self(), addr, 16, false, VM_PROT_READ | VM_PROT_EXECUTE);	//set cur protection

	if(kret != KERN_SUCCESS || kret2 != KERN_SUCCESS)
	{
		NSLog(@"ERROR PROTECTING");
		return 0;
	}

	NSLog(@"trampoline created at %llX", (unsigned long long)addr);

	NSLog(@"%X | %X | %X | %X", read32(mach_task_self(),addr), read32(mach_task_self(),addr + 4), read32(mach_task_self(),addr + 8), read32(mach_task_self(),addr + 12));

	return addr;
}

void parseMemory(vm_address_t addr, vm_offset_t length)
{
	for(vm_address_t curAddr = addr; curAddr <= addr + length; curAddr = curAddr + 4)
	{
		uint32_t v = read32(mach_task_self(), curAddr);
		//NSLog(@"--- %llX = %lX", (unsigned long long)curAddr, (unsigned long)v);

		if(v == 0xD4001001)
		{
			NSLog(@"syscall at %8lX", (unsigned long)(curAddr));

			vm_address_t trampoline = create_trampoline(curAddr);

			uint32_t bInstruction = b(curAddr, trampoline);

			MSHookMemory((void*)curAddr, &bInstruction, sizeof(bInstruction));

			/*

			   NSLog(@"syscall at %8lX", (unsigned long)(curAddr));

			                  uint32_t blInstruction = bl(curAddr, interceptAddr);

			                  MSHookMemory((void*)curAddr, &blInstruction, sizeof(blInstruction));

			 */

			//FF 03 01 D1 //sub pc, pc, 0x40



			//MSHookFunction((void*)(curAddr), (void *)syscallIntercept, (void **)&orgSyscall);

			/*uint32_t nop = CFSwapInt32(0xE00300AA);

			   MSHookMemory((void*)curAddr, &nop, sizeof(nop));*/

			uint32_t v2 = read32(mach_task_self(), curAddr);

			NSLog(@"new value = %llX", (unsigned long long)v2);
		}
	}
}

void syscallIntercept()
{
	//NSLog(@"!!!!!!! shit works!");

	__asm("svc #0x80");

	//__asm("svc #0x80"); //syscall

	//NSLog(@"just called svc");

	/*#ifdef __LP64__
	   __asm("mov x0, #0x42");
	 #else
	   exit(42);
	 #endif*/



	/*NSLog(@"!!!!!!! shit works!");
	   //orgSyscall();

	   //volatile asm("bl =0x100967D10");

	   //volatile asm("bl =0xFF09670FF");

	 */
}

%ctor
{
	Dl_info info;
	if(!dladdr((const void*)syscallIntercept, &info))
	{
		NSLog(@"ERROR FINDING POINTER!");
		return;
	}

	dylibPath = info.dli_fname;
	interceptAddr = (vm_address_t)info.dli_saddr;

	NSLog(@"dylib path = %s, saddr = %llX", dylibPath, (unsigned long long)interceptAddr);

  #ifdef __LP64__
	parseMachHeaderCommands((mach_header_64*)_dyld_get_image_header(0), _dyld_get_image_vmaddr_slide(0));
  #else
	parseMachHeaderCommands(_dyld_get_image_header(0), _dyld_get_image_vmaddr_slide(0));
  #endif
}
