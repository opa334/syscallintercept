- (void)exit_syscall
{
	#if __LP64__ //64 Bit
	__asm("mov x16, #0x01"); //Systemcall Nummer wird von Register x16 bezogen (EXIT = 0x01)
	__asm("mov x0, #0x01"); //Argument 1 (Nummer bei beenden des Programms)
	__asm("svc #0x80"); //Aufruf des Systemcalls
	#else //32 Bit
	__asm("mov r12, #0x01"); //Systemcall Nummer wird von Register r12 bezogen (EXIT = 0x01)
	__asm("mov r0, #0x01"); //Argument 1 (Nummer bei beenden des Programms)
	__asm("svc #0x80"); //Aufruf des Systemcalls
	#endif
}

- (NSInteger)getpid_syscall
{
	NSInteger pid = 0;

	#if __LP64__ //64 Bit
	__asm("mov x16, #0x14"); //Systemcall Nummer wird von Register x16 bezogen (GETPID = 0x14)
	__asm("svc #0x80"); //Aufruf des Systemcalls (return wert wird in x0 gespeichert)
	__asm("mov %0, x0" : "=r"(pid)); //x0 in lokale variable pid kopieren
	#else //32 Bit
	__asm("mov r12, #0x14"); //Systemcall Nummer wird von Register r12 bezogen (GETPID = 0x14)
	__asm("svc #0x80"); //Aufruf des Systemcalls (return wert wird in r0 gespeichert)
	__asm("mov %0, r0" : "=r"(pid)); //r0 in lokale variable pid kopieren
	#endif

	return pid;
}
