@interface SCRootViewController : UIViewController
{
  UISegmentedControl* _methodPicker;
  UISegmentedControl* _syscallPicker;
  UILabel* _outputLabel;
  UIButton* _goButton;
}

- (void)goButtonPressed;
- (void)exit_syscall;
- (NSInteger)getpid_syscall;

@end
