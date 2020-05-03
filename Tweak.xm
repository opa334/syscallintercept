//I don't know what I did to get MSHookMemory to compile, but I remember getting an updated substrate.h somewhere and linking a newer substrate version

#include "substrate.h"

#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/reloc.h>

#include <sys/utsname.h>

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
volatile void space();

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

	//NSLog(@"mh = %llX", (unsigned long long)mh);

	uintptr_t addr = (uintptr_t)(mh + 1);

	//NSLog(@"addr = %llX, size = %llX", (unsigned long long)addr, (unsigned long long)sizeof(mh));

	uintptr_t endAddr = addr + mh->sizeofcmds;

	for(int ci = 0; ci < mh->ncmds && addr <= endAddr; ci++)
	{
		cmd = (typeof(cmd))addr;

		addr = addr + cmd->cmdsize;

		if(cmd->cmd != LC_SEGMENT_64 || strcmp(cmd->segname, "__TEXT"))	//We only care about __TEXT segments (do we really?)
		{
			continue;
		}

		parseMemory(cmd->vmaddr + slide, cmd->vmsize);

		//NSLog(@"- segname = %s, cmd = %lX, vmaddr = %llX, vmsize = %llX, nsects = %lu, cmdsize = %lu", cmd->segname, (unsigned long)cmd->cmd, (unsigned long long)cmd->vmaddr, (unsigned long long)cmd->vmsize, (unsigned long)cmd->nsects, (unsigned long)cmd->cmdsize);

		if(cmd->nsects > 0)
		{
			sect = (typeof(sect))((uintptr_t)cmd + sizeof(cmd));
			for(unsigned long si = 0; si < cmd->nsects; si++)
			{
				sect = sect + 1;

				//addr = addr + sizeof(sect);

				//NSLog(@"-- sectname %s, addr = %llX, offset = %llX, size = %llX", sect->sectname, (unsigned long long)sect->addr, (unsigned long long)sect->offset, (unsigned long long)sect->size);
			}
		}
	}
}

//Generates a pc relative "b" instruction based on the origin and the target passed
//The offset between those may not be too big (I think +/- 2^24 at most), else the b instruction cannot be generated
uint32_t b(vm_address_t origin, vm_address_t target)
{
	NSLog(@"!b(%llX, %llX)", (unsigned long long)origin, (unsigned long long)target);

	int32_t offset = (target - origin) / 4;

	//NSLog(@"b");

	//NSLog(@"origin = %llX | target = %llX", (unsigned long long)origin, (unsigned long long)target);

	NSLog(@"offset = %i", offset);

	if(offset < 0)
	{
		if((offset & 0b1111110000000000000000000000000) != 0b1111110000000000000000000000000)
		{
			NSLog(@"B ERROR: OFFSET TOO SMALL");
		}
	}
	else
	{
		if((offset & 0b1111110000000000000000000000000) != 0)
		{
			NSLog(@"B ERROR: OFFSET TOO BIG");
		}
	}

	uint32_t bl = 0b00010100000000000000000000000000 | (offset & 0b00000011111111111111111111111111);

	return bl;
}

//Same as above but it generates a "bl" instruction
uint32_t bl(vm_address_t origin, vm_address_t target)
{
	NSLog(@"!bl(%llX, %llX)", (unsigned long long)origin, (unsigned long long)target);
	int32_t offset = (target - origin) / 4;

	//NSLog(@"bl");

	//NSLog(@"origin = %llX | target = %llX", (unsigned long long)origin, (unsigned long long)target);

	NSLog(@"offset = %i", offset);

	if(offset < 0)
	{
		if((offset & 0b1111110000000000000000000000000) != 0b1111110000000000000000000000000)
		{
			NSLog(@"BL ERROR: OFFSET TOO SMALL");
		}
	}
	else
	{
		if((offset & 0b1111110000000000000000000000000) != 0)
		{
			NSLog(@"BL ERROR: OFFSET TOO BIG");
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

vm_size_t ps;

uint32_t pageSize()
{
	if(ps)
	{
		return ps;
	}

	/*struct utsname u;
	   uname(&u);
	   host_page_size(mach_host_self(), &ps);
	   if (strstr(u.machine, "iPad5,") == u.machine)
	   {
	        ps = 4096;	// this is 4k but host_page_size lies to us
	   }*/

	ps = 128;

	return ps;
}

vm_address_t memStart;
uint32_t memCurOff = 0;
vm_address_t spaceAddr;

//An attempt to allocate memory to use as jump destination. Wouldn't work because the offset would be bigger than 2^24 (the max offset for b)

/*void allocIfNeeded(vm_address_t at, size_t size)
   {
        NSLog(@"!allocIfNeeded(%llX, %llX)", (unsigned long long)at, (unsigned long long)size);*/
/*vm_address_t at = 0;

   //NSLog(@"GANG");

   for(vm_address_t tmpAddr = nearby; tmpAddr > 0; tmpAddr -= pageSize())
   {
        //NSLog(@"x");
 #ifdef __LP64__
        vm_region_basic_info_64_t info = NULL;
        mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64;
        vm_address_t actAddr = tmpAddr;
        vm_size_t size = pageSize();
        //NSLog(@"d");
        kern_return_t ret = vm_region_64(mach_task_self(), &actAddr, &size, VM_REGION_BASIC_INFO, (vm_region_info_64_t)&info, &cnt, NULL);
        //NSLog(@"f");
 #else
        vm_region_basic_info_t info = NULL;
        mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64;
        vm_address_t actAddr = tmpAddr;
        vm_size_t size = pageSize();
        kern_return_t ret = vm_region(mach_task_self(), &actAddr, &size, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &cnt, NULL);
 #endif

        if(ret == KERN_INVALID_ADDRESS)
        {
                //NSLog(@"found %llX", (unsigned long long)at);
                at = tmpAddr;
                break;
        }
   }*/

//NSLog(@"%llX", (unsigned long long)at);

/*kern_return_t kret;
   vm_address_t addr = at;

   if(((memCurOff + size) >= pageSize()) || memStart == 0)
   {
        kret = vm_allocate(mach_task_self(), &addr, pageSize(), false);	//Allocate next available space

        if(kret != KERN_SUCCESS)
        {
                NSLog(@"Error allocating space: %i", kret);
        }

        kret = vm_protect(mach_task_self(), addr, 16, true, VM_PROT_READ | VM_PROT_EXECUTE);	//set max protection

        if(kret != KERN_SUCCESS)
        {
                //NSLog(@"Error setting max protection: %i", kret);
        }

        kret = vm_protect(mach_task_self(), addr, 16, false, VM_PROT_READ | VM_PROT_EXECUTE);	//set cur protection

        if(kret != KERN_SUCCESS)
        {
                //NSLog(@"Error setting current protection: %i", kret);
        }

        //NSLog(@"allocated zone at %llX with size %i", (unsigned long long)addr, pageSize());

        memStart = addr;
        memCurOff = 0;

        NSLog(@"allocated at %llX", (unsigned long long)memStart);
   }
   }*/

vm_address_t create_call(vm_address_t origin)
{
	NSLog(@"!create_call(%llX)", (unsigned long long)origin);
	vm_address_t ret = origin + 4;

	//allocIfNeeded(origin - 1048576, 16);
	memStart = spaceAddr;

	vm_address_t addr = (memStart + memCurOff);

	//NSLog(@"!!! %llX = (%llX + %i)", (unsigned long long)addr, (unsigned long long)memStart, memCurOff);

	//The code below works under the assumption that the x30 register is unused, there is probably a better way to do this (maybe saving all registers to the stack?)

	uint32_t saveX30 = CFSwapInt32(0xF2031EAA);	//mov x18, x30
	//NSLog(@"!!! interceptCall");
	uint32_t interceptCall = bl(addr + 4, interceptAddr);
	uint32_t loadX30 = CFSwapInt32(0xFE0312AA);	//mov x30, x18
	//NSLog(@"!!! jumpBack");
	uint32_t jumpBack = b(addr + 12, ret);

	uint32_t call[4] = { saveX30, interceptCall, loadX30, jumpBack };

	//kret = vm_write(mach_task_self(), addr, (vm_offset_t)trampoline, sizeof(trampoline));
	MSHookMemory((void*)addr, (const void*)call, sizeof(call));

	memCurOff += sizeof(call);

	//NSLog(@"call created at %llX", (unsigned long long)addr);

	//NSLog(@"%X | %X | %X | %X", read32(mach_task_self(),addr), read32(mach_task_self(),addr + 4), read32(mach_task_self(),addr + 8), read32(mach_task_self(),addr + 12));

	return addr;
}

void parseMemory(vm_address_t addr, vm_offset_t length)
{
	for(vm_address_t curAddr = addr; curAddr <= addr + length; curAddr = curAddr + 4)
	{
		uint32_t v = read32(mach_task_self(), curAddr);
		////NSLog(@"--- %llX = %lX", (unsigned long long)curAddr, (unsigned long)v);

		if(v == 0xD4001001)
		{
			NSLog(@"syscall at %8lX", (unsigned long)(curAddr));

			vm_address_t call = create_call(curAddr);

			uint32_t bInstruction = b(curAddr, call);

			MSHookMemory((void*)curAddr, &bInstruction, sizeof(bInstruction));

			/*

			   //NSLog(@"syscall at %8lX", (unsigned long)(curAddr));

			                  uint32_t blInstruction = bl(curAddr, interceptAddr);

			                  MSHookMemory((void*)curAddr, &blInstruction, sizeof(blInstruction));

			 */

			//FF 03 01 D1 //sub pc, pc, 0x40



			//MSHookFunction((void*)(curAddr), (void *)syscallIntercept, (void **)&orgSyscall);

			/*uint32_t nop = CFSwapInt32(0xE00300AA);

			   MSHookMemory((void*)curAddr, &nop, sizeof(nop));*/

			//uint32_t v2 = read32(mach_task_self(), curAddr);

			//NSLog(@"new value = %llX", (unsigned long long)v2);
		}
	}
}

//Using anything but direct asm here will probably crash unless all registers are saved before calling this and restored afterwards (currently this isn't the case)
void syscallIntercept()
{
	//NSLog(@"!!!!!!! shit works!");

	#ifdef __LP64__
	__asm("mov x0, #0x539");
	#endif

	__asm("svc #0x80");	//syscall

	//NSLog((@"!!!!!!! shit ends!");

	////NSLog(@"just called svc");

	//#ifdef __LP64__
	//__asm("mov x0, #0x539");
	/*#else
	   exit(42);*/
	//#endif

	/*//NSLog(@"!!!!!!! shit works!");
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
		//NSLog(@"ERROR FINDING POINTER!");
		return;
	}

	dylibPath = info.dli_fname;
	interceptAddr = (vm_address_t)info.dli_saddr;

	if(!dladdr((const void*)space, &info))
	{
		//NSLog(@"ERROR FINDING POINTER!");
		return;
	}

	spaceAddr = (vm_address_t)info.dli_saddr;

	//NSLog(@"dylib path = %s, saddr = %llX", dylibPath, (unsigned long long)interceptAddr);

	//Right now only the first image (the app binary) is parsed, it could be desirable to also parse frameworks and stuff however

  #ifdef __LP64__
	parseMachHeaderCommands((mach_header_64*)_dyld_get_image_header(0), _dyld_get_image_vmaddr_slide(0));
  #else
	parseMachHeaderCommands(_dyld_get_image_header(0), _dyld_get_image_vmaddr_slide(0));
  #endif
}


//By far not the best solution, but the only thing that I could get working with a low enough offset for the b instruction to work (800 bytes for now)
//This is overwritten at runtime in the create_call function
//In order for this intercept thing to fully work, it would be needed to figure out a way to allocate memory that can be jumped to, then this wouldn't be needed
volatile void space()	
{
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
	__asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop"); __asm("nop");
}
