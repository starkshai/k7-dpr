module top (
    input  wire        clk_p,
    input  wire        clk_n,
    output wire [3:0]  shift_low_out,
    input  wire        key1,
    input  wire        key2,
    // SPI Flash interface (regular I/O, shared with config pins after boot)
    output wire        flash_ce_b,
    output wire        flash_d0,
    input  wire        flash_d1,
    output wire        flash_d2,
    output wire        flash_d3,
    output wire        fan_pwm
);

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam DEBOUNCE_SIZE           = 21;
    localparam C_NUM_TRIGGERS_VS_SHIFT = 4;
    localparam C_ICAP_DATA_WIDTH       = 32;

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    wire clk_100;

    reg  [15:0] reset_vector = 16'hFFFF;
    wire        rst;
    wire        por_rst_n;

    // Debounced buttons (active-low input -> active-high internal)
    wire key1_dbnc;
    wire key2_dbnc;

    // Virtual Socket signals (shift only)
    wire [3:0]  vs_shift_hw_triggers;
    wire [31:0] vs_shift_axis_status;
    wire        vs_shift_rm_shutdown_req;
    // Shift RM has no real shutdown handshake; ack must be tied high (per UG947
    // reference) or the PRC stalls in HW_SHUTDOWN and never commits the load.
    (* dont_touch = "true" *) wire vs_shift_rm_shutdown_ack = 1'b1;
    (* dont_touch = "true" *) wire vs_shift_rm_decouple;
    (* dont_touch = "true" *) wire vs_shift_rm_reset;

    // ICAP interface
    wire [31:0] icap_i;
    wire [31:0] icap_o;
    wire        icap_csib;
    wire        icap_rdwrb;
    wire        cap_req;

    // AXI memory interface (PRC <-> SPI Flash Reader)
    wire [31:0] m_axi_mem_araddr;
    wire [7:0]  m_axi_mem_arlen;
    wire [2:0]  m_axi_mem_arsize;
    wire [1:0]  m_axi_mem_arburst;
    wire [2:0]  m_axi_mem_arprot;
    wire [3:0]  m_axi_mem_arcache;
    wire [3:0]  m_axi_mem_aruser;
    wire        m_axi_mem_arvalid;
    wire        m_axi_mem_arready;
    wire [31:0] m_axi_mem_rdata;
    wire [1:0]  m_axi_mem_rresp;
    wire        m_axi_mem_rlast;
    wire        m_axi_mem_rvalid;
    wire        m_axi_mem_rready;

    // JTAG to AXI Lite interface
    wire [31:0] m_axi_awaddr;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;
    wire [31:0] m_axi_araddr;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rvalid;
    wire        m_axi_rready;

    // ILA probe wires
    wire [0:0] vs_shift_rm_shutdown_req_v;
    wire [0:0] vs_shift_rm_shutdown_ack_v;
    wire [0:0] vs_shift_rm_decouple_v;
    wire [0:0] vs_shift_rm_reset_v;

    wire [0:0] icap_csib_v;
    wire [0:0] icap_rdwrb_v;
    wire [3:0] icap_status;

    wire [0:0] m_axi_mem_arvalid_v;
    wire [0:0] m_axi_mem_arready_v;
    wire [0:0] m_axi_mem_rlast_v;
    wire [0:0] m_axi_mem_rvalid_v;
    wire [0:0] m_axi_mem_rready_v;

    wire [0:0] m_axi_awvalid_v;
    wire [0:0] m_axi_awready_v;
    wire [0:0] m_axi_wvalid_v;
    wire [0:0] m_axi_wready_v;
    wire [0:0] m_axi_bvalid_v;
    wire [0:0] m_axi_bready_v;
    wire [0:0] m_axi_arvalid_v;
    wire [0:0] m_axi_arready_v;
    wire [0:0] m_axi_rvalid_v;
    wire [0:0] m_axi_rready_v;

    // STARTUPE2 signals (CCLK only — data pins are regular I/O)
    wire        usrcclkts;
    wire        usrcclko;

    // ICAP clock: drive the PRC ICAP domain and ICAPE2 from clk_100 directly,
    // matching the UG947 reference (single clock domain, no CDC). A divided
    // 25 MHz icap_clk put the PRC's ICAP completion logic in a separate domain
    // and the partial load never committed.
    wire        icap_clk;
    assign icap_clk = clk_100;

    // -------------------------------------------------------------------------
    // Reset logic (key2 active-low -> active-high internal rst)
    // -------------------------------------------------------------------------
    assign rst = reset_vector[0] | ~key2_dbnc;
    assign por_rst_n = ~reset_vector[0];

    always @(posedge clk_100) begin
        reset_vector <= {1'b0, reset_vector[15:1]};
    end

    // -------------------------------------------------------------------------
    // Clock generation: 200MHz differential -> 100MHz single-ended
    // -------------------------------------------------------------------------
    clocks U0_clocks (
        .clk_p   (clk_p),
        .clk_n   (clk_n),
        .rst     (1'b0),
        .clk_out (clk_100)
    );

    // -------------------------------------------------------------------------
    // Virtual Socket 0: shift (the only RP module)
    // -------------------------------------------------------------------------
    // Note: addr is driven by a free-running counter for the BRAM-based shift
    reg [34:0] count_value;
    always @(posedge clk_100) begin
        if (rst)
            count_value <= 35'b0;
        else
            count_value <= count_value + 1;
    end

    shift inst_shift (
        .en       (vs_shift_rm_reset),
        .clk      (clk_100),
        .addr     (count_value[34:23]),
        .data_out (shift_low_out)
    );

    // -------------------------------------------------------------------------
    // Partial Reconfiguration Controller
    // -------------------------------------------------------------------------
    prc i_prc (
        .clk                              (clk_100),
        .reset                            (rst),
        // vs_shift interface
        .vsm_vs_shift_hw_triggers         (vs_shift_hw_triggers),
        .vsm_vs_shift_rm_shutdown_req     (vs_shift_rm_shutdown_req),
        .vsm_vs_shift_rm_shutdown_ack     (vs_shift_rm_shutdown_ack),
        .vsm_vs_shift_rm_decouple         (vs_shift_rm_decouple),
        .vsm_vs_shift_rm_reset            (vs_shift_rm_reset),
        .vsm_vs_shift_m_axis_status_tdata (vs_shift_axis_status),
        .vsm_vs_shift_m_axis_status_tvalid(),
        // ICAP interface
        .icap_clk                         (icap_clk),
        .icap_reset                       (rst),
        .icap_i                           (icap_o),
        .icap_o                           (icap_i),
        .icap_csib                        (icap_csib),
        .icap_rdwrb                       (icap_rdwrb),
        .cap_req                          (cap_req),
        .cap_gnt                          (1'b1),
        .cap_rel                          (1'b0),
        // AXI Lite register interface (from JTAG)
        .s_axi_reg_awaddr                 (m_axi_awaddr),
        .s_axi_reg_awvalid                (m_axi_awvalid),
        .s_axi_reg_awready                (m_axi_awready),
        .s_axi_reg_wdata                  (m_axi_wdata),
        .s_axi_reg_wvalid                 (m_axi_wvalid),
        .s_axi_reg_wready                 (m_axi_wready),
        .s_axi_reg_bresp                  (m_axi_bresp),
        .s_axi_reg_bvalid                 (m_axi_bvalid),
        .s_axi_reg_bready                 (m_axi_bready),
        .s_axi_reg_araddr                 (m_axi_araddr),
        .s_axi_reg_arvalid                (m_axi_arvalid),
        .s_axi_reg_arready                (m_axi_arready),
        .s_axi_reg_rdata                  (m_axi_rdata),
        .s_axi_reg_rresp                  (m_axi_rresp),
        .s_axi_reg_rvalid                 (m_axi_rvalid),
        .s_axi_reg_rready                 (m_axi_rready),
        // AXI memory interface (to SPI Flash Reader)
        .m_axi_mem_araddr                 (m_axi_mem_araddr),
        .m_axi_mem_arlen                  (m_axi_mem_arlen),
        .m_axi_mem_arsize                 (m_axi_mem_arsize),
        .m_axi_mem_arburst                (m_axi_mem_arburst),
        .m_axi_mem_arprot                 (m_axi_mem_arprot),
        .m_axi_mem_arcache                (m_axi_mem_arcache),
        .m_axi_mem_aruser                 (m_axi_mem_aruser),
        .m_axi_mem_arvalid                (m_axi_mem_arvalid),
        .m_axi_mem_arready                (m_axi_mem_arready),
        .m_axi_mem_rdata                  (m_axi_mem_rdata),
        .m_axi_mem_rresp                  (m_axi_mem_rresp),
        .m_axi_mem_rlast                  (m_axi_mem_rlast),
        .m_axi_mem_rvalid                 (m_axi_mem_rvalid),
        .m_axi_mem_rready                 (m_axi_mem_rready)
    );

    // -------------------------------------------------------------------------
    // Hardware triggers from key1 (active-low, trigger on press)
    //   Toggle mechanism: each key1 press switches between RMs
    //   trigger[0]=1 -> rm_shift_left, trigger[1]=1 -> rm_shift_right
    //
    //   The trigger must be a short PULSE, never a held level. trigger[1] is
    //   the POR RM's own trigger, so driving it from ~reconfig_toggle keeps it
    //   asserted forever at power-on and the PRC reloads rm_shift_right
    //   back-to-back with no gap: the RM region is disabled for the whole
    //   ~300 ms load, so the LED walks once and then freezes. Both triggers
    //   must also be idle-low, exactly like the UG947 reference buttons.
    // -------------------------------------------------------------------------
    localparam integer TRIG_PULSE_BITS = 16;   // 65536 clk_100 = 655 us pulse

    reg  key1_dbnc_d1 = 1'b0;
    reg  reconfig_toggle = 1'b0;
    reg  [TRIG_PULSE_BITS-1:0] trig_pulse_cnt = {TRIG_PULSE_BITS{1'b0}};
    wire key1_rising = key1_dbnc & ~key1_dbnc_d1;
    wire trig_active = |trig_pulse_cnt;

    always @(posedge clk_100) begin
        key1_dbnc_d1 <= key1_dbnc;
        if (rst) begin
            reconfig_toggle <= 1'b0;
            trig_pulse_cnt  <= {TRIG_PULSE_BITS{1'b0}};
        end else if (trig_active) begin
            trig_pulse_cnt <= trig_pulse_cnt - 1'b1;
        end else if (key1_rising) begin
            reconfig_toggle <= ~reconfig_toggle;
            trig_pulse_cnt  <= {TRIG_PULSE_BITS{1'b1}};
        end
    end

    assign vs_shift_hw_triggers[0] = trig_active &  reconfig_toggle;
    assign vs_shift_hw_triggers[1] = trig_active & ~reconfig_toggle;
    assign vs_shift_hw_triggers[2] = 1'b0;
    assign vs_shift_hw_triggers[3] = 1'b0;

    // -------------------------------------------------------------------------
    // ILA probe signal packing
    // -------------------------------------------------------------------------
    assign vs_shift_rm_shutdown_req_v[0] = vs_shift_rm_shutdown_req;
    assign vs_shift_rm_shutdown_ack_v[0] = vs_shift_rm_shutdown_ack;
    assign vs_shift_rm_decouple_v[0]     = vs_shift_rm_decouple;
    assign vs_shift_rm_reset_v[0]        = vs_shift_rm_reset;

    assign icap_csib_v[0]  = icap_csib;
    assign icap_rdwrb_v[0] = icap_rdwrb;
    assign icap_status     = icap_o[7:4];

    assign m_axi_mem_arvalid_v[0] = m_axi_mem_arvalid;
    assign m_axi_mem_arready_v[0] = m_axi_mem_arready;
    assign m_axi_mem_rlast_v[0]   = m_axi_mem_rlast;
    assign m_axi_mem_rvalid_v[0]  = m_axi_mem_rvalid;
    assign m_axi_mem_rready_v[0]  = m_axi_mem_rready;

    assign m_axi_awvalid_v[0] = m_axi_awvalid;
    assign m_axi_awready_v[0] = m_axi_awready;
    assign m_axi_wvalid_v[0]  = m_axi_wvalid;
    assign m_axi_wready_v[0]  = m_axi_wready;
    assign m_axi_bvalid_v[0]  = m_axi_bvalid;
    assign m_axi_bready_v[0]  = m_axi_bready;
    assign m_axi_arvalid_v[0] = m_axi_arvalid;
    assign m_axi_arready_v[0] = m_axi_arready;
    assign m_axi_rvalid_v[0]  = m_axi_rvalid;
    assign m_axi_rready_v[0]  = m_axi_rready;

    // -------------------------------------------------------------------------
    // Debug: ILA vs_shift
    // -------------------------------------------------------------------------
    ila_vs_shift i_ila_vs_shift (
        .clk          (clk_100),
        .trig_out     (),
        .trig_out_ack (1'b1),
        .probe0       (vs_shift_hw_triggers),
        .probe1       (vs_shift_rm_shutdown_req_v),
        .probe2       (vs_shift_rm_shutdown_ack_v),
        .probe3       (vs_shift_rm_decouple_v),
        .probe4       (vs_shift_rm_reset_v),
        .probe5       (vs_shift_axis_status)
    );

    // -------------------------------------------------------------------------
    // Debug: ILA ICAP
    // -------------------------------------------------------------------------
    ila_icap i_ila_icap (
        .clk          (icap_clk),
        .trig_out     (),
        .trig_out_ack (1'b1),
        .probe0       (icap_i),
        .probe1       (icap_status),
        .probe2       (icap_csib_v),
        .probe3       (icap_rdwrb_v)
    );

    // -------------------------------------------------------------------------
    // Debug: ILA AXI memory
    // -------------------------------------------------------------------------
    ila_axi_mem i_ila_axi_mem (
        .clk     (clk_100),
        .probe0  (m_axi_mem_araddr),
        .probe1  (m_axi_mem_arlen),
        .probe2  (m_axi_mem_arsize),
        .probe3  (m_axi_mem_arburst),
        .probe4  (m_axi_mem_arprot),
        .probe5  (m_axi_mem_arcache),
        .probe6  (m_axi_mem_aruser),
        .probe7  (m_axi_mem_arvalid_v),
        .probe8  (m_axi_mem_arready_v),
        .probe9  (m_axi_mem_rdata),
        .probe10 (m_axi_mem_rresp),
        .probe11 (m_axi_mem_rlast_v),
        .probe12 (m_axi_mem_rvalid_v),
        .probe13 (m_axi_mem_rready_v),
        .probe14 (spi_dbg_state),
        .probe15 (spi_dbg_seq),
        .probe16 (flash_ce_b),
        .probe17 (usrcclko),
        .probe18 (flash_d0),   // MOSI as driven by the reader
        .probe19 (flash_d1)    // MISO as seen on the pad (through the IBUF)
    );

    // -------------------------------------------------------------------------
    // Debug: ILA AXI register
    // -------------------------------------------------------------------------
    ila_axi_reg i_ila_axi_reg (
        .clk     (clk_100),
        .probe0  (m_axi_awaddr),
        .probe1  (m_axi_awvalid_v),
        .probe2  (m_axi_awready_v),
        .probe3  (m_axi_wdata),
        .probe4  (m_axi_wvalid_v),
        .probe5  (m_axi_wready_v),
        .probe6  (m_axi_bresp),
        .probe7  (m_axi_bvalid_v),
        .probe8  (m_axi_bready_v),
        .probe9  (m_axi_araddr),
        .probe10 (m_axi_arvalid_v),
        .probe11 (m_axi_arready_v),
        .probe12 (m_axi_rdata),
        .probe13 (m_axi_rresp),
        .probe14 (m_axi_rvalid_v),
        .probe15 (m_axi_rready_v)
    );

    // -------------------------------------------------------------------------
    // JTAG to AXI Master
    // -------------------------------------------------------------------------
    jtag_to_axi i_jtag_to_axi (
        .aclk          (clk_100),
        .aresetn       (por_rst_n),
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awprot  (),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),
        .m_axi_bresp   (m_axi_bresp),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready),
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arprot  (),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),
        .m_axi_rdata   (m_axi_rdata),
        .m_axi_rresp   (m_axi_rresp),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rready  (m_axi_rready)
    );

    // -------------------------------------------------------------------------
    // ICAP E2 primitive
    // -------------------------------------------------------------------------
    ICAPE2 #(
        .DEVICE_ID  (32'h03651093),
        .ICAP_WIDTH ("X32")
    ) ICAPE2_inst (
        .O     (icap_o),
        .CLK   (icap_clk),
        .CSIB  (icap_csib),
        .I     (icap_i),
        .RDWRB (icap_rdwrb)
    );

    // -------------------------------------------------------------------------
    // STARTUPE2 primitive: share SPI configuration interface at runtime
    // -------------------------------------------------------------------------
    STARTUPE2 #(
        .PROG_USR ("FALSE")
    ) STARTUPE2_inst (
        .CFGCLK     (),
        .CFGMCLK    (),
        .EOS        (),
        .PREQ       (),
        .CLK        (clk_100),
        .GSR        (1'b0),
        .GTS        (1'b0),
        .KEYCLEARB  (1'b1),
        .PACK       (1'b0),
        .USRCCLKO   (usrcclko),
        .USRCCLKTS  (usrcclkts),
        .USRDONEO   (1'b1),
        .USRDONETS  (1'b1)
    );

    // -------------------------------------------------------------------------
    // SPI Flash Reader: bridges PRC m_axi_mem to SPI Flash via STARTUPE2
    // -------------------------------------------------------------------------
    wire [3:0] spi_dbg_state;
    wire [3:0] spi_dbg_seq;

    spi_flash_reader i_spi_flash_reader (
        .clk              (clk_100),
        .rst              (rst),
        // AXI read slave (to PRC)
        .s_axi_araddr     (m_axi_mem_araddr),
        .s_axi_arlen      (m_axi_mem_arlen),
        .s_axi_arsize     (m_axi_mem_arsize),
        .s_axi_arburst    (m_axi_mem_arburst),
        .s_axi_arcache    (m_axi_mem_arcache),
        .s_axi_arprot     (m_axi_mem_arprot),
        .s_axi_arvalid    (m_axi_mem_arvalid),
        .s_axi_arready    (m_axi_mem_arready),
        .s_axi_rdata      (m_axi_mem_rdata),
        .s_axi_rresp      (m_axi_mem_rresp),
        .s_axi_rlast      (m_axi_mem_rlast),
        .s_axi_rvalid     (m_axi_mem_rvalid),
        .s_axi_rready     (m_axi_mem_rready),
        // SPI clock (to STARTUPE2 for CCLK pin)
        .spi_clk_o        (usrcclko),
        .spi_clk_ts       (usrcclkts),
        // SPI data pins (regular I/O)
        .spi_ce_b         (flash_ce_b),
        .spi_d0_o         (flash_d0),
        .spi_d1_i         (flash_d1),
        // Debug
        .dbg_state        (spi_dbg_state),
        .dbg_seq          (spi_dbg_seq)
    );

    // WP and HOLD pins tied high (not used in Quad I/O read)
    assign flash_d2 = 1'b1;
    assign flash_d3 = 1'b1;

    // Fan PWM control (active-low, tied low for now)
    assign fan_pwm = 1'b0;

    // STARTUPE2 drives CCLK (B10) internally.
    // Data pins (CE_B, D0-D3) are regular I/O connected to top-level ports.

    // -------------------------------------------------------------------------
    // Button debouncers (active-low input)
    // -------------------------------------------------------------------------
    debouncer #(.C_WIDTH(DEBOUNCE_SIZE)) i_key1_dbnc (
        .clk               (clk_100),
        .input_to_debounce (key1),
        .debounced_signal  (key1_dbnc)
    );

    debouncer #(.C_WIDTH(DEBOUNCE_SIZE)) i_key2_dbnc (
        .clk               (clk_100),
        .input_to_debounce (key2),
        .debounced_signal  (key2_dbnc)
    );

endmodule
