/*volatile void test()
{
  asm volatile ( "bl %0" : : "g"(syscallIntercept) ); //02 00 00 94
}*/

/*void printRightBL()
{
  Dl_info info;
  if(!dladdr((const void*)test, &info))
  {
    NSLog(@"ERROR FINDING POINTER!");
    return;
  }

  vm_address_t testAddr = (vm_address_t)info.dli_saddr;

  uint32_t real_bl = read32(mach_task_self(), testAddr);

  NSLog(@"---- REAL BL: %llX", (unsigned long long)real_bl);

  uint32_t fake_bl = bl(testAddr, interceptAddr);

  NSLog(@"---- FAKE BL: %llX", (unsigned long long)fake_bl);

  MSHookMemory((void*)testAddr, &fake_bl, sizeof(fake_bl));

  uint32_t real_fake_bl = read32(mach_task_self(), testAddr);

  NSLog(@"---- REAL FAKE BL: %llX", (unsigned long long)real_fake_bl);
}*/

/*cmd = (typeof(cmd))mh+1;

for(int cmdI = 0; cmdI < mh->ncmds; cmdI++)
{

  if(cmd->nsects > 0)
  {
    NSLog(@"- segname = %s, vmaddr = %llX, vmsize = %llX", cmd->segname, (unsigned long long)cmd->vmaddr, (unsigned long long)cmd->vmsize);

    sect = (typeof(sect))cmd+1;

    for(int sectI = 0; sectI < cmd->nsects; sectI++)
    {
      NSLog(@"-- sectname %s, addr = %llX, offset = %llX, size = %llX", sect->sectname, (unsigned long long)sect->addr, (unsigned long long)sect->offset, (unsigned long long)sect->size);

      sect = sect + 1;
    }

    cmd = (typeof(cmd))sect;
  }
  else
  {
    cmd = cmd + 1;
  }
}*/

/*command = (typeof(command))mh+1;

NSLog(@"mh = %p, command = %p", mh, command);
void* endAddr = (void*)(addr + (void*)mh->sizeofcmds);

for(int i = 0; i < mh->ncmds && addr < endAddr; i++)
{
  NSLog(@"- segname = %s, vmaddr = %llX, vmsize = %llX", commands[i]->segname, (unsigned long long)command->vmaddr, (unsigned long long)command->vmsize);

  for(int s = 0; s < command->nsects; s++)
  {
    #ifdef __LP64__
    const struct section_64* sect;
    #else
    const struct section* sect;
    #endif
    sect = (command + sizeof(command)) + (sizeof(sect) * s);

    NSLog(@"-- sectname %s, addr = %llX, offset = %llX, size = %llX", sect->sectname, (unsigned long long)sect->addr, (unsigned long long)sect->offset, (unsigned long long)sect->size);
  }

  //NSLog(@"- addr = %p", addr);

  addr = (void*)(command + command->cmdsize);
}*/

/*vm_address_t magicAddr = (vm_address_t)(mh);

NSLog(@"magicAddr = %llx", (unsigned long long)magicAddr);

uint32_t magicRead = read32(mach_task_self(), magicAddr);

NSLog(@"magicRead = %llx", (unsigned long long)magicRead);

NSLog(@"mh = %p", mh);*/
