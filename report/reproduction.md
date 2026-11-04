# 从零复现

环境：Windows 10/11、Vivado 2024.1及Artix UltraScale+支持、Python 3.9以上。2024.1用于与提供的IP配置及归档报告一致，重新使用其他工具版本须重新生成IP并检查结果。

## 获取源码

```powershell
git clone https://github.com/maxshushu7-del/fpga-h2-sensing.git E:/Codex/FPGA/workspace/h2_submission
Set-Location E:/Codex/FPGA/workspace/h2_submission
```

`release_manifest.json`列出发布文件SHA-256；`build/reports/fresh_create_project.log`记录新目录创建工程及三项IP生成。归档bitstream对应V4原RTL；本次新增的是接收端、构建入口与交付材料，没有更改板级控制RTL。

## 接收端与无硬件验证

```powershell
Set-Location src/host/gui
python -m venv E:/Codex/FPGA/workspace/h2_gui_env
E:/Codex/FPGA/workspace/h2_gui_env/Scripts/python.exe -m pip install --cache-dir E:/Codex/FPGA/workspace/pip_cache -r requirements.txt
E:/Codex/FPGA/workspace/h2_gui_env/Scripts/python.exe -m unittest test_v4_integration test_udp_protocol -v
E:/Codex/FPGA/workspace/h2_gui_env/Scripts/python.exe main.py
```

12项检查覆盖V4字段、端序与单位、结果序号、失效清除、原始码、温度来源、数据报回环，以及既有H2PK/JSON/ADC分块入口。fixture回环与真正接板分别记录。匹配命令行接收器在`src/fpga/host/udp_monitor.py`。

## 创建FPGA工程

在仓库根目录运行：

```powershell
./build/scripts/create_project.ps1 -VivadoBin E:/Xilinx/Vivado/2024.1/bin
```

随后打开`src/fpga/project/contest_all.xpr`。核对器件`xcau15p-ffvb676-2-i`、顶层`laser_lock_hw_udp_only_top`、FFT点数4096、ILA/VIO及约束。运行综合、实现、生成bitstream；归档自身的Timing Summary、Utilization、DRC、CDC和Route Status。新目录创建已重放，既有WNS +0.006 ns是所附2026-11-03布局布线报告的数据，不能视为任意重建的固定保证。

## 数字验证

`src/fpga/scripts/udp_sim.tcl`对应网络帧测试。完整测频与跨模型反例见`migration/project_cross_review/README.md`；FIR迁移见`migration/fir_trial`。技能目录的三个SKILL交代输入、执行、验收和失效条件；历史日志保留其原工具与路径，重新运行须保存新的输入和日志。

## 上板与数据

同次bit/ltx在`board/bitstream`。先核对供电、AD/DA接口、输入范围与时钟初始化，再启用采样及测频；输出授权应按执行器接口确认。PC使用`192.168.1.100/24`等空闲地址，监听5001。VIO测频使能及ILA触发步骤见[独立JTAG操作说明](../board/scripts/jtag_measurement.md)。先核对来源地址、包序号、FFT序号和有效位，再观察图形显示。

`data/measured`是队员提供的信号源读数转录；`data/reference`是RTL运行导出的频谱。温度标志标明V4热对象模型来源。原始照片在`board/photos`，相应条件不能互相替代。
