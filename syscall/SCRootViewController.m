#import "SCRootViewController.h"

@implementation SCRootViewController

- (void)viewDidLoad
{
	self.view.backgroundColor = [UIColor whiteColor];

	_methodPicker = [[UISegmentedControl alloc] initWithItems:@[@"Syscall", @"C Funktion"]];
	_methodPicker.selectedSegmentIndex = 0;
	_methodPicker.translatesAutoresizingMaskIntoConstraints = NO;

	_syscallPicker = [[UISegmentedControl alloc] initWithItems:@[@"exit", @"getpid"]];
	_syscallPicker.selectedSegmentIndex = 0;
	_syscallPicker.translatesAutoresizingMaskIntoConstraints = NO;

	_outputLabel = [[UILabel alloc] init];
	_outputLabel.translatesAutoresizingMaskIntoConstraints = NO;

	_goButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[_goButton addTarget:self action:@selector(goButtonPressed) forControlEvents:UIControlEventTouchUpInside];
	[_goButton setTitle:@"go" forState:UIControlStateNormal];
	_goButton.titleLabel.font = [_goButton.titleLabel.font fontWithSize:24];
	_goButton.translatesAutoresizingMaskIntoConstraints = NO;

	[self.view addSubview:_methodPicker];
	[self.view addSubview:_syscallPicker];
	[self.view addSubview:_outputLabel];
	[self.view addSubview:_goButton];

	NSDictionary* views = NSDictionaryOfVariableBindings(_methodPicker, _syscallPicker, _outputLabel, _goButton);

	[self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-[_goButton]-|" options:0 metrics:nil views:views]];
	[self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-[_methodPicker]-|" options:0 metrics:nil views:views]];
	[self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-[_syscallPicker]-|" options:0 metrics:nil views:views]];
	[self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-[_outputLabel]-|" options:0 metrics:nil views:views]];

	[self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-50-[_outputLabel]-20-[_methodPicker]-20-[_syscallPicker]-20-[_goButton]" options:0 metrics:nil views:views]];
}

- (void)goButtonPressed
{
	if(_methodPicker.selectedSegmentIndex == 0)
	{
		if(_syscallPicker.selectedSegmentIndex == 0)
		{
			[self exit_syscall];
		}
		else if(_syscallPicker.selectedSegmentIndex == 1)
		{
			int pid = [self getpid_syscall];

			_outputLabel.text = [NSString stringWithFormat:@"PID: %i", pid];
		}
	}
	else if(_methodPicker.selectedSegmentIndex == 1)
	{
		if(_syscallPicker.selectedSegmentIndex == 0)
		{
			exit(1);
		}
		else if(_syscallPicker.selectedSegmentIndex == 1)
		{
			int pid = getpid();

			_outputLabel.text = [NSString stringWithFormat:@"PID: %i", pid];
		}
	}
}

- (void)exit_syscall
{
	#if __LP64__	//64 Bit
	__asm("mov x16, #0x01");//Systemcall Nummer wird von Register x16 bezogen (EXIT = 0x01)
	__asm("mov x0, #0x01");	//Argument 1 (Nummer bei beenden des Programms)
	__asm("svc #0x80");	//Aufruf des Systemcalls
	#else	//32 Bit
	__asm("mov r12, #0x01");//Systemcall Nummer wird von Register r12 bezogen (EXIT = 0x01)
	__asm("mov r0, #0x01");	//Argument 1 (Nummer bei beenden des Programms)
	__asm("svc #0x80");	//Aufruf des Systemcalls
	#endif

	NSLog(@"we still running");
}

- (NSInteger)getpid_syscall
{
	NSInteger pid = 0;

	#if __LP64__	//64 Bit
	__asm("mov x16, #0x14");//Systemcall Nummer wird von Register x16 bezogen (GETPID = 0x14)
	__asm("svc #0x80");	//Aufruf des Systemcalls (return wert wird in x0 gespeichert)
	__asm("mov %0, x0" : "=r" (pid));	//x0 in lokale variable pid kopieren
	#else	//32 Bit
	__asm("mov r12, #0x14");//Systemcall Nummer wird von Register r12 bezogen (GETPID = 0x14)
	__asm("svc #0x80");	//Aufruf des Systemcalls (return wert wird in r0 gespeichert)
	__asm("mov %0, r0" : "=r" (pid));	//r0 in lokale variable pid kopieren
	#endif

	return pid;
}

@end
