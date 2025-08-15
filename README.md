# SystemRDL Register Block Comparison

This repository contains a comprehensive comparison and verification framework for register blocks generated from SystemRDL specifications, specifically comparing OBI (Open Bus Interface) and APB (Advanced Peripheral Bus) implementations.

## Overview

The project demonstrates the generation and verification of register blocks using the [PeakRDL-regblock](https://github.com/DanielKellerM/PeakRDL-regblock) tool, comparing two different bus interface implementations:

- **OBI (Open Bus Interface)**: A modern, high-performance bus protocol
- **APB (Advanced Peripheral Bus)**: A traditional, simple bus protocol commonly used in ARM-based systems

The main focus is on an iDMA (intelligent Direct Memory Access) register block, which serves as a practical example for comparing these two bus interface implementations.

## Project Structure

```
.
├── idma_reg.rdl              # SystemRDL specification for iDMA registers
├── regblock/                 # Generated register block implementations
│   ├── idma_reg_obi.sv      # OBI interface implementation
│   ├── idma_reg_obi_pkg.sv  # OBI package definitions
│   ├── idma_reg_apb.sv      # APB interface implementation
│   └── idma_reg_apb_pkg.sv  # APB package definitions
├── obi_to_apb.sv            # OBI to APB protocol adapter
├── tb_idma_reg_obi_vs_apb.sv # Testbench comparing both implementations
├── Makefile                 # Build and simulation automation
├── requirements.txt         # Python dependencies
└── common_cells/           # Common SystemVerilog utilities
```

## Features

### Register Block Generation
- **SystemRDL Specification**: Complete iDMA register specification with configuration, status, and control registers
- **Dual Interface Support**: Automatic generation for both OBI and APB interfaces
- **Parameterized Design**: Configurable address width, number of dimensions, and protocol bits

### Protocol Comparison
- **OBI Interface**: Modern bus protocol with advanced features like burst transfers and optional signals
- **APB Interface**: Traditional ARM AMBA protocol with simple, reliable operation
- **Protocol Adapter**: OBI-to-APB bridge for interoperability

### Verification Framework
- **Comprehensive Testbench**: Verifies functional equivalence between OBI and APB implementations
- **Protocol Compliance**: Ensures both implementations follow their respective bus protocols
- **Automated Testing**: Makefile-based build and simulation workflow

## Prerequisites

### Required Tools
- **ModelSim/QuestaSim**: For SystemVerilog simulation
- **Python 3.7+**: For PeakRDL tools
- **Make**: For build automation

### Python Dependencies
```bash
pip install -r requirements.txt
```

The requirements include:
- `peakrdl`: SystemRDL parser and processing tools
- `peakrdl-regblock`: Register block generator (custom fork with OBI support)

## Quick Start

### 1. Setup Environment
```bash
# Install Python dependencies
pip install -r requirements.txt

# Or use virtual environment
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Generate Register Blocks
```bash
make generate-regblocks
```

This will generate both OBI and APB register block implementations from the SystemRDL specification.

### 3. Run Verification
```bash
# Compile and run simulation
make sim

# Or run with GUI
make sim-gui
```

## Build Targets

The Makefile provides several useful targets:

- `generate-regblocks`: Generate register blocks from SystemRDL
- `compile`: Compile all SystemVerilog sources
- `sim`: Run command-line simulation
- `sim-gui`: Run simulation with GUI
- `clean`: Remove generated files and simulation artifacts

## Register Block Details

### iDMA Register Map

The iDMA register block includes the following registers:

- **Configuration Register (`conf`)**: DMA settings including burst length, protocol selection, and decoupling options
- **Status Register (`status`)**: Current DMA status and busy indicators
- **Next ID Register (`next_id`)**: Launch new transfers and get transfer setup status
- **Done ID Register (`done_id`)**: Retrieve completed transfer IDs
- **Source/Destination Address Registers**: Memory addresses for DMA operations
- **Dimension Registers**: Multi-dimensional transfer configuration

## License

This project is licensed under the Solderpad Hardware License, Version 0.51. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **ETH Zurich and University of Bologna**: Original iDMA design
- **PeakRDL Team**: SystemRDL processing tools
- **ETH Zurich, University of Bologna and OpenHW Group**: OBI protocol specification

## Related Projects

- [PeakRDL-regblock](https://github.com/DanielKellerM/PeakRDL-regblock): Register block generator with OBI support
- [common_cells](https://github.com/pulp-platform/common_cells): Common SystemVerilog utilities
- [apb](https://github.com/pulp-platform/apb): APB protocol implementation
- [obi](https://github.com/pulp-platform/obi): OBI protocol implementation
