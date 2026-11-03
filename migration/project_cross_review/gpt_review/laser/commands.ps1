Set-Location -LiteralPath 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\gpt_review\laser'
# Replay from E:/Codex/FPGA/workspace/report_targeted_revision_20261102/project_cross_review/gpt_review/laser
# All RTL and existing tests are read from inputs; no production changes.
$p='E:/Codex/FPGA/workspace/report_targeted_revision_20261102/project_cross_review/inputs'
$v='E:/Xilinx/Vivado/2024.1/bin'
& ($v+'/xvlog.bat') ($p+'/rtl/laser/auto_lock_fsm.v') ($p+'/existing_tests/laser/tb_auto_lock_fsm.v')
& ($v+'/xelab.bat') tb_auto_lock_fsm -s existing_fsm
& ($v+'/xsim.bat') existing_fsm -runall
& ($v+'/xvlog.bat') ($p+'/rtl/laser/auto_lock_fsm.v') 'tb_auto_lock_endpoint.v'
& ($v+'/xelab.bat') tb_auto_lock_endpoint -s endpoint
& ($v+'/xsim.bat') endpoint -runall
& ($v+'/xvlog.bat') ($p+'/rtl/laser/pi2d_controller.v') ($p+'/rtl/laser/saturation.v') 'tb_pi2d_review.v'
& ($v+'/xelab.bat') tb_pi2d_review -s pi_review
& ($v+'/xsim.bat') pi_review -runall
& ($v+'/xvlog.bat') ($p+'/rtl/laser/auto_lock_uart.v') ($p+'/existing_tests/laser/tb_auto_lock_uart.v')
& ($v+'/xelab.bat') tb_auto_lock_uart -s existing_uart
& ($v+'/xsim.bat') existing_uart -runall

