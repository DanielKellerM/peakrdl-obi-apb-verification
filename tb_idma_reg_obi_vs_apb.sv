// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Testbench to verify OBI vs APB register block implementations
// Uses OBI interface properly with a subordinate driver

`timescale 1ns/1ps

// Include OBI typedefs
`include "obi/include/obi/typedef.svh"

// OBI Interface Driver
interface obi_driver #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH = 1
) (
    input wire clk_i,
    input wire rst_ni
);

    // OBI typedefs
    `OBI_TYPEDEF_MINIMAL_A_OPTIONAL(obi_a_optional_t)
    `OBI_TYPEDEF_MINIMAL_R_OPTIONAL(obi_r_optional_t)
    `OBI_TYPEDEF_TYPE_A_CHAN_T(obi_a_chan_t, logic [ADDR_WIDTH-1:0], logic [DATA_WIDTH-1:0], logic [DATA_WIDTH/8-1:0], logic [ID_WIDTH-1:0], obi_a_optional_t)
    `OBI_TYPEDEF_TYPE_R_CHAN_T(obi_r_chan_t, logic [DATA_WIDTH-1:0], logic [ID_WIDTH-1:0], obi_r_optional_t)
    `OBI_TYPEDEF_REQ_T(obi_req_t, obi_a_chan_t)
    `OBI_TYPEDEF_RSP_T(obi_rsp_t, obi_r_chan_t)

    // OBI interface signals
    obi_req_t obi_req;
    obi_rsp_t obi_rsp;

    // Memory model for register storage
    logic [DATA_WIDTH-1:0] memory [bit [ADDR_WIDTH-1:0]];

    // Clocking block for synchronized access
    default clocking cb @(posedge clk_i);
        default input #1step output #1;
        input obi_req;
        output obi_rsp;
    endclocking

    // Reset task
    task automatic reset();
        cb.obi_rsp.gnt <= '0;
        cb.obi_rsp.rvalid <= '0;
        cb.obi_rsp.r.rdata <= '0;
        cb.obi_rsp.r.rid <= '0;
        cb.obi_rsp.r.err <= '0;
        cb.obi_rsp.r.r_optional <= '0;
        memory.delete(); // Clear memory
    endtask

    always_ff @(posedge clk_i) begin
  
    end

    // Task to read memory directly (for verification)
    task automatic read_memory(logic [ADDR_WIDTH-1:0] addr, output logic [DATA_WIDTH-1:0] data);
        data = memory.exists(addr) ? memory[addr] : '0;
    endtask

endinterface

module tb_idma_reg_obi_vs_apb;

    // Clock and reset
    logic clk;
    logic rst_n;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset generation
    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end

 
    // Instantiate APB register block

    obi_to_apb #(
        // TODO
    ) u_obi_to_apb (
        // TODO
    );

    // Instantiate APB register block
    idma_reg_apb u_idma_reg_apb (
        .clk(clk),
        .rst(rst_n),
        .s_apb_psel(apb_psel),
        .s_apb_penable(apb_penable),
        .s_apb_pwrite(apb_pwrite),
        .s_apb_pprot(apb_pprot),
        .s_apb_paddr(apb_paddr),
        .s_apb_pwdata(apb_pwdata),
        .s_apb_pstrb(apb_pstrb),
        .s_apb_pready(apb_pready),
        .s_apb_prdata(apb_prdata),
        .s_apb_pslverr(apb_pslverr),
        .hwif_in(hwif_in_apb),
        .hwif_out(hwif_out_apb)
    );


endmodule
