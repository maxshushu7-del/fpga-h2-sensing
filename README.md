# fpga-h2-sensing
An FPGA-based adaptive system locks a narrow-linewidth laser to the resonance slope for optical hydrogen sensing, analyzes kHz-to-hundreds-of-MHz beat signals by FFT, compensates temperature drift in closed loop, and interfaces with a host for configuration and monitoring.

## 项目名称

**FPGA-Based Adaptive High-Precision Hydrogen Sensing System**

基于FPGA的自适应高精度氢气传感系统

## 提交材料导航

本仓库按AMD自主选题指南推荐结构建立以下七个主目录。目录说明先建立，源码、数据、日志和最终报告按入口归档。

| 目录 | 用途 |
|---|---|
| [src](src/README.md) | FPGA源码、约束、系数、IP配置和PC端程序 |
| [sim](sim/README.md) | 仿真平台、验证脚本与原始结果 |
| [build](build/README.md) | 可复现构建脚本、综合及实现报告 |
| [board](board/README.md) | bit/ltx、接线、上板步骤、照片及实测输出 |
| [data](data/README.md) | 测试输入、参考数据与原始记录 |
| [skill](skill/README.md) | 可复用技能、工作流与迁移案例 |
| [report](report/README.md) | 报告、AI协作记录、海报和演示材料入口 |

## 开发平台

- 开发板：ALINX AXAU15；器件：AMD Artix UltraScale+ XCAU15P。
- ADC：AD9643；DAC：AD9122。
- 工具：Vivado2024.1。使用版本及复现条件在报告中说明。

## 从哪里开始阅读

1. 查看[要求与目录对照](report/requirements.md)。
2. 按[从零复现入口](report/reproduction.md)组织工具、构建、数字验证和上板步骤。
3. 查看[AI协作记录](report/ai_collaboration/README.md)及独立[Skill入口](skill/README.md)。

仓库中保留确定提交版本；历史对比只保留有来源、参数及对应日志的必要材料。目录和文件名使用英文，正文可以使用中文。大文件可通过Release分发，在对应目录补充固定下载链接。

## 许可证

沿用本仓库已有的[MIT许可证](LICENSE)。
