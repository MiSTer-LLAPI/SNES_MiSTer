/* HDL implementation of Low-Latency API protocol
* 
* Copyright 2019 Jamie Dickson aka Kitrinx
* 
* Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
* documentation files (the "Software"), to deal in the Software without restriction, including without limitation
* the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
* and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included in all copies or substantial portions
* of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
* TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
* CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
* IN THE SOFTWARE.
*/

// Feb, 1 2019 - Initial Release

// ***** NOTE ******
// On IO board 5.5 the bliss box requires external pull-up resistors to communicate properly

// Data payload bit order:

// Byte 0:
// uint8_t Controller Type (or error code)
// Notable ID's are:
// 18 - NES
// 21 - Gen 3 button
// 22 - Gen 6 button
// 27 - SNES
// 28 - NES Zapper
// 41 - Atari Paddles
// 51 - NeGcon
// 65 - PSX Digital
// 11 - PSX DS
// 12 - PSX DS2
// more info: https://docs.google.com/document/d/12XpxrmKYx_jgfEPyw-O2zex1kTQZZ-NSBdLO2RQPRzM/edit

// Bytes 1-2:
// Buttons
// XXX: These are not accurate in 3.0, see the linked document instead
// System SNES    Genesis PSX    Gun   Saturn
//  0:     Y       A       □      Click A
//  1:     B       B       ×      Light B
//  2:     X       X       △      NA    X
//  3:     A       Y       ○      NA    Y
//  4:     Select  Mode    Select NA    NA
//  5:     Start   Start   Start  NA    Start
//  6:     LT      NA      L1     NA    L
//  7:     RT      NA      R1     NA    R

//  8:     NA      Z       L2     NA    Z
//  9:     NA      C       R2     NA    C
// 10:     U       U       U      NA    NA
// 11:     D       D       D      NA    NA
// 12:     L       L       L      NA    NA
// 13:     R       R       R      NA    NA
// 14:     0       NA      L3     NA    NA
// 15:     1       NA      R3     NA    NA

// 16:     2       NA      NA     NA    NA
// 17:     3       NA      NA     NA    NA
// 18:     4       NA      NA     NA    NA
// 19:     5       NA      NA     NA    NA
// 20:     6       NA      NA     NA    NA
// 21:     7       NA      NA     NA    NA
// 22:     8       NA      NA     NA    NA
// 23: This bit can be the "special" trigger button for retroarch
// more info: https://docs.google.com/spreadsheets/d/1Bk3j5kaKfV1tOfzCq3GLKFsff027RdmwOuSfBLM3Ims/edit#gid=0

// Bytes 4-12: (uint8_t's)
// 04: Axis 1 X
// 05: Axis 1 Y
// 06: Axis 1 Z
// 07: Axis 2 X
// 08: Axis 2 Y
// 09: Axis 2 Z
// 10: Slider
// 11: Dial
// 12: Hat

// Modes:
// 0: autopause state
// 1:
// 2: 
// 3: Hotswap Disabled
// 4: UDLR mode
// 5: Analog to D-pad
// 6: autopause dis.
// 7: d-pad only mode

module LLAPI_Enhanced #(
    parameter bit AUTO_MODES = 1,
    parameter bit COMMAND_INTERFACE = 0,
    parameter bit ALLOW_MODE_WRITES = 0,
    parameter bit RAW_COMMANDS = 0,
    parameter bit IMMEDIATE_REPOLL = 0
)
(
	input         CLK_50M,
	input         ENABLE,        // If 0, module will be disabled and pins will be set to Z
	input         IO_LATCH_IN,   // D+ top level IO pin
	output reg    IO_LATCH_OUT,
	input         IO_DATA_IN,    // D- top level IO pin
	output reg    IO_DATA_OUT,
	input         LLAPI_SYNC,     // Pos edge corresponds with when the core needs the data, from core
	output        LLAPI_EN,       // High when device is communicating, passed to core
	output [7:0]  LLAPI_TYPE,     // Enumerated controller type, passed to core
	output [7:0]  LLAPI_MODES,    // Modes that the bliss box may be in, passed to core
	output [31:0] LLAPI_BUTTONS,  // Vector of buttons, 1 == pressed, passed to core
	output [71:0] LLAPI_ANALOG,   // Unsigned 8 bit vector of analog axis, passed to core
    input CMD_VALID,
    input [7:0] CMD_OPCODE,
    input [15:0] CMD_PAYLOAD, // low byte first: duration, then level for 1C
    output CMD_READY,
    output reg CMD_DONE,
    output reg [7:0] CMD_ERROR, // 0=completed, E0=timeout, E1=rejected, E2=premature raw reply
    output reg [103:0] CMD_REPLY,
    output reg [3:0] CMD_REPLY_LENGTH,
    output reg MODES_VALID,
    // CLK_50M domain. VALID refers to the last complete status snapshot,
    // not proof of physical presence. UPDATE/FAULT are one-cycle events.
    output STATUS_VALID,
    output reg STATUS_UPDATE,
    output reg LINK_FAULT,
    // Valid only with LINK_FAULT: 1 timeout, 2 rejected status, 3 receive-phase watchdog.
    output [1:0] FAULT_REASON,
    // Pulse with the new complete snapshot on a direct valid-to-valid ID change.
    output reg TYPE_CHANGED,
    // Persists through successful reports and rediscovery until this port is disabled.
    output reg [1:0] LAST_FAULT_REASON,
    // Extension command descriptor, sampled with CMD_VALID && CMD_READY.
    input CMD_RAW,
    input [4:0] CMD_TX_LENGTH,
    input [3:0] CMD_RX_LENGTH,
    input [191:0] CMD_TX_DATA
);

// Commands
enum bit [7:0] {
	LLAPI_POLL               = 8'h00, // Holds latch low until done
	LLAPI_STATUS             = 8'h01, // Returns 13 bytes, see above
	LLAPI_PRESSURE_STATUS    = 8'h02, // Returns 13 bytes: player ID then 12 pressures
	LLAPI_SET_MODES          = 8'h20, // Requires 1 byte payload
	LLAPI_GET_MODES          = 8'h21, // Returns bit field of active modes, 1 byte. see above
	// Rumble
	LLAPI_RUMBLE_CONST_START_FROM_PARMS = 8'h11, //must set parms first
	LLAPI_RUBMLE_CONST_END              = 8'h12,
	LLAPI_RUMBLE_SINE_START_FROM_PARMS  = 8'h14, //must set parms first
	LLAPI_RUMBLE_SINE_END               = 8'h18,
	LLAPI_RUMBLE_CONST_JOLT             = 8'h1A,
	LLAPI_RUMBLE_SINE_JOLT              = 8'h1B,
	LLAPI_RUMBLE_PARMS                  = 8'h1C //followed by 2 bytes of data containing the parms (duration and then level)
} commands;

// Errors
enum bit [7:0] {
	LLAPI_ERROR_NODATA       = 8'h00,
	LLAPI_ERROR_AP_NO_REPORT = 8'hFF
} errors;

// Timing (one 50mhz cycle == 0.02us)
enum bit [20:0] {
	TIME_POLL   = 21'd350000, // 7ms - default polling period if no sync is used
	TIME_SETTLE = 21'd150,    // 3us - to account for bidirectional IO pins slew rate
	TIME_WAIT   = 21'd500,    // 10us - time to wait after a reply before writing again
	TIME_LEADIN = 21'd84,     // 1.5us - at start of new transactions
	TIME_BIT_H  = 21'd109,    // 2.2us - always-high first bit-half
	TIME_BIT_R  = 21'd115,    // 2.3us - variable second bit-half
	TIME_SYNC_H = 21'd49,     // 1us - sync pulse between bytes high time
	TIME_SYNC_L = 21'd50,     // 1us - sync pulse between bytes low time
	TIME_BUFFER = 21'd9500    // 3 scanlines of wiggle room
} time_periods;

typedef enum bit [3:0] {
	READ_IDLE,
	READ_POLL,
	WRITE_STATUS,
	READ_STATUS,
	WRITE_SETUP,
	WRITE_MODES,
	READ_MODES,
    READ_COMMAND,
    WRITE_PAYLOAD
} execution_stage;

typedef enum bit [3:0] {
	STATE_IDLE,
	STATE_WRITE_START,
	STATE_WRITE,
	STATE_WRITE_END,
	STATE_READ_START,
	STATE_READ_WAIT,
	STATE_READ,
	STATE_READ_END,
    STATE_WAIT_RELEASE
} execution_state;

// Conservative receive-start limit: 1 ms at 50 MHz; requires hardware validation.
localparam [20:0] RECEIVE_START_TIMEOUT = 21'd50000;

logic [20:0]  cycle, poll_offset, poll_counter, poll_offset_latch, sync_counter;
// count reaches at most TIME_WAIT+1=501; larger values reset before increment commits.
localparam integer COUNT_WIDTH = $clog2(TIME_WAIT + 2);
logic [COUNT_WIDTH-1:0] count;
localparam bit RAW_ENABLED = COMMAND_INTERFACE && RAW_COMMANDS;
localparam integer WRITE_BITS = RAW_ENABLED ? 200 : 32;
logic [WRITE_BITS-1:0] write_buffer;
logic [3:0]   write_length;
logic [2:0]   read_bit; // Relies on overflow
logic [3:0]   read_byte;
logic [7:0]   read_buffer[13];
logic [3:0]   read_length;

logic repoll_pending;
logic modes_attempted, command_busy, command_slot;
localparam integer PAYLOAD_COUNT_BITS = RAW_ENABLED ? 5 : 2;
logic [PAYLOAD_COUNT_BITS-1:0] payload_remaining;
wire request_raw = RAW_ENABLED && CMD_RAW;
logic raw_selected;
wire raw_active = RAW_ENABLED && command_busy && raw_selected;
logic [7:0] active_opcode;
localparam integer TRANSACTION_LIMIT = TIME_POLL > RECEIVE_START_TIMEOUT ? TIME_POLL : RECEIVE_START_TIMEOUT;
localparam integer TRANSACTION_WIDTH = $clog2(TRANSACTION_LIMIT + 1);
logic [TRANSACTION_WIDTH-1:0] transaction_timer;
function automatic valid_command(input [7:0] op);
    valid_command = op == 8'h02 || op == 8'h21 || op == 8'h11 || op == 8'h12 ||
        op == 8'h14 || op == 8'h18 || op == 8'h1a || op == 8'h1b || op == 8'h1c ||
        (ALLOW_MODE_WRITES && op == 8'h20);
endfunction
// The built-in scheduler owns poll/status; mode writes retain their typed opt-in.
wire extension_valid = CMD_OPCODE > 8'h01 && CMD_OPCODE != 8'h20 &&
    !valid_command(CMD_OPCODE) && CMD_TX_LENGTH <= 24 && CMD_RX_LENGTH <= 13;

function automatic protocol_error(input [7:0] v);
    protocol_error = v == 8'hf1 || v == 8'hfe || v == 8'hff;
endfunction
logic [31:0] pending_buttons;
logic [71:0] pending_analog;
// Decode the receive buffer directly; public registers still update only after packet_complete.
assign pending_buttons = {
							4'd0, 
							(read_buffer[12][3] ? 4'd0 :
							{
								(read_buffer[12][2:0] == 3'h0 || read_buffer[12][2:0] == 3'h1 || read_buffer[12][2:0] == 3'h7), //U
								(read_buffer[12][2:0] == 3'h4 || read_buffer[12][2:0] == 3'h3 || read_buffer[12][2:0] == 3'h5), //D
								(read_buffer[12][2:0] == 3'h6 || read_buffer[12][2:0] == 3'h5 || read_buffer[12][2:0] == 3'h7), //L
								(read_buffer[12][2:0] == 3'h2 || read_buffer[12][2:0] == 3'h1 || read_buffer[12][2:0] == 3'h3) //R
							}),
							read_buffer[3],
							read_buffer[2],
							read_buffer[1]
						};
assign pending_analog = {
							read_buffer[12],
							read_buffer[11],
							read_buffer[10],
							read_buffer[9],
							read_buffer[8],
							read_buffer[7],
							read_buffer[6],
							read_buffer[5],
							read_buffer[4]
						};
logic [7:0] pending_type;
logic packet_complete;
logic [31:0]  lljs_buttons;
logic [71:0]  lljs_analog;
logic [7:0]   lljs_type;
logic [7:0]   lljs_modes;

reg   [20:0]  poll_time = TIME_POLL;

logic latch;
logic is_latched;
logic data_in, data_out;
logic enable;
logic old_sync, new_sync, old_data;

execution_stage stage = READ_IDLE;
execution_state state = STATE_IDLE;

wire auxiliary = command_busy || stage == READ_MODES;
wire repoll_due = IMMEDIATE_REPOLL && repoll_pending && stage == READ_IDLE;
wire transaction_active = state != STATE_WAIT_RELEASE && (stage != READ_IDLE || state != STATE_IDLE || repoll_due);
wire watchdog_expired = transaction_active &&
    transaction_timer >= ((stage == READ_POLL || raw_active) ? TIME_POLL : RECEIVE_START_TIMEOUT);
wire premature_reply = raw_active && state == STATE_IDLE && stage == WRITE_PAYLOAD && is_latched;
wire poll_due = sync_counter >= ((enable && poll_time > TIME_BUFFER &&
    poll_offset < poll_time - TIME_BUFFER) ? poll_time - poll_offset : poll_time);
assign CMD_READY = COMMAND_INTERFACE && ENABLE && enable && command_slot &&
    !command_busy && stage == READ_IDLE && state == STATE_IDLE &&
    !is_latched && data_in && (!poll_due || repoll_due) && cycle > TIME_WAIT;
assign LLAPI_TYPE = lljs_type;
assign LLAPI_BUTTONS = lljs_buttons;
assign LLAPI_ANALOG = lljs_analog;
assign LLAPI_MODES = lljs_modes;
assign LLAPI_EN = enable;
// Reuse existing snapshot identity and link state: no extra validity register.
assign STATUS_VALID = ENABLE && enable && lljs_type != 0 && !protocol_error(lljs_type);

assign FAULT_REASON = LINK_FAULT ? LAST_FAULT_REASON : 2'd0;

always_comb begin
	if (latch) begin
		IO_LATCH_OUT = 1'b0;
		IO_DATA_OUT = data_out;
	end else begin
		IO_LATCH_OUT = 1'b1;
		IO_DATA_OUT = 1'b1;
	end
end

// Use the regular synchronous disable path on the first clock after FPGA configuration.
logic startup_complete = 1'b0;
always_ff @(posedge CLK_50M) begin
    startup_complete <= 1'b1;
    if (ENABLE && startup_complete) begin
    CMD_DONE <= 0; STATUS_UPDATE <= 0; TYPE_CHANGED <= 0; LINK_FAULT <= 0;
    if (transaction_active) begin
        if (transaction_timer != {TRANSACTION_WIDTH{1'b1}}) transaction_timer <= transaction_timer + 1'b1;
    end else transaction_timer <= 0;
	old_sync <= new_sync;
	new_sync <= LLAPI_SYNC;
	cycle <= cycle + 1'b1;

	if (~latch) begin
		is_latched <= ~IO_LATCH_IN;
		old_data <= data_in;
		data_in <= IO_DATA_IN;
	end

	if (~old_sync && new_sync && sync_counter > poll_offset_latch) begin
		sync_counter <= 0;
		poll_time <= poll_counter > (TIME_BUFFER + TIME_WAIT) ? poll_counter - TIME_BUFFER : TIME_POLL; // about 3 scanlines of wobble room
		poll_counter <= 0;
	end else begin
		if (sync_counter != 21'h1fffff) sync_counter <= sync_counter + 1'b1;
		if (poll_counter != 21'h1fffff) poll_counter <= poll_counter + 1'b1;
	end

	if (stage == READ_POLL || stage == READ_STATUS)
		if (poll_offset != 21'h1fffff) poll_offset <= poll_offset + 1'b1;

    // The deadline wins the entire clock, including status and auxiliary reply publication.
    if (watchdog_expired || premature_reply) begin
        repoll_pending <= 0;
        if (is_latched || !data_in) state <= STATE_WAIT_RELEASE; else state <= STATE_IDLE;
        stage <= READ_IDLE; cycle <= 0; count <= 0; transaction_timer <= 0;
        latch <= 0; data_out <= 1; packet_complete <= 0; payload_remaining <= 0;
        LINK_FAULT <= 1;
        LAST_FAULT_REASON <= (state == STATE_READ || state == STATE_READ_WAIT) ? 2'd3 : 2'd1;
        if (premature_reply && !watchdog_expired) LAST_FAULT_REASON <= 2'd2;
        if (command_busy) begin
            CMD_DONE <= 1;
            CMD_ERROR <= watchdog_expired ? 8'he0 : 8'he2;
            command_busy <= 0;
        end
        if (!auxiliary || is_latched || !data_in) begin
            enable <= 0; lljs_type <= 0; lljs_buttons <= 0;
            lljs_analog <= 72'h080000808080808080;
            lljs_modes <= 0; MODES_VALID <= 0; modes_attempted <= 0;
        end
    end else case (state)
		STATE_IDLE: begin
			if (is_latched) begin // remote device wants to talk
				enable <= 1'b1;
				cycle <= 0;
				count <= 0;
				read_byte <= 0;
                packet_complete <= 0;
				state <= STATE_READ_START;
			end else if (stage == WRITE_PAYLOAD) begin
                if (cycle > TIME_WAIT && data_in) begin
                    cycle <= 0; state <= STATE_WRITE_START; stage <= READ_COMMAND;
                end
            end else if (CMD_READY && CMD_VALID) begin
                command_slot <= 0; CMD_ERROR <= 0; CMD_REPLY <= 0; CMD_REPLY_LENGTH <= 0;
                if (!(request_raw ? extension_valid : valid_command(CMD_OPCODE))) begin CMD_DONE <= 1; CMD_ERROR <= 8'he1; end
                else begin
                    command_busy <= 1; active_opcode <= CMD_OPCODE; raw_selected <= request_raw;
                    write_buffer <= request_raw ? {CMD_TX_DATA, CMD_OPCODE} : {CMD_PAYLOAD, CMD_OPCODE};
                    payload_remaining <= request_raw ? CMD_TX_LENGTH : CMD_OPCODE == 8'h1c ? 2 : (CMD_OPCODE == 8'h20 ? 1 : 0);
                    read_length <= request_raw ? CMD_RX_LENGTH : CMD_OPCODE == 8'h02 ? 13 : (CMD_OPCODE == 8'h21 ? 1 : 0);
                    stage <= READ_COMMAND; state <= STATE_WRITE_START;
                    cycle <= 0; transaction_timer <= 0;
                end
            end else if (stage == WRITE_STATUS) begin // We just got a poll result
				if (cycle > TIME_WAIT) begin
					cycle <= 0;
					state <= STATE_WRITE_START;
					stage <= READ_STATUS;
					read_length <= 'd13;
					write_buffer <= {24'd0, LLAPI_STATUS};
				end
			end else if (stage == WRITE_MODES) begin
				if (cycle > TIME_WAIT) begin
					cycle <= 0;
					stage <= READ_MODES;
					read_length <= 1'd1;
					state <= STATE_WRITE_START;
					write_buffer <= {24'd0, LLAPI_GET_MODES};
				end
			end else if (repoll_due || (poll_due && !auxiliary)) begin // Let an accepted auxiliary transaction finish or time out.
				count <= count + 1'b1;
				if (repoll_due ?
                    (cycle > TIME_WAIT && data_in) : count > TIME_WAIT) begin
                    repoll_pending <= 0;
					if (stage != READ_IDLE) begin // IO timeout, device disconnect/defunct
						enable <= 1'b0; LINK_FAULT <= 1; LAST_FAULT_REASON <= 2'd1;
						poll_offset <= 0;
						poll_time <= poll_offset_latch > TIME_BUFFER ? poll_offset_latch : TIME_POLL;
						poll_offset_latch <= 21'd350000;
						lljs_buttons <= 24'h0;
						lljs_type <= 8'h0;
						lljs_analog <= 72'h080000808080808080;
                        lljs_modes <= 0; MODES_VALID <= 0; modes_attempted <= 0;
					end
					poll_offset <= 0;
					sync_counter <= 0;
					cycle <= 0;
					count <= 0;
					read_length <= 0;
					state <= STATE_WRITE_START;
                    transaction_timer <= 0; payload_remaining <= 0;
					stage <= READ_POLL;
					write_buffer <= {24'd0, LLAPI_POLL};
				end
			end
		end

		STATE_WRITE_START: begin
			if (cycle == 0) begin
				data_out <= 1'b0; 
				latch <= 1'b1; // Take control
				write_length <= 'h8; // Always 8 for now
			end else if (cycle >= TIME_LEADIN) begin
				cycle <= 0;
				state <= STATE_WRITE;
			end
		end

		STATE_WRITE: begin
			if (write_length == 0) begin
				state <= STATE_WRITE_END;
				cycle <= 0;
			end else if (cycle == 'd0) begin // high half-bit
				data_out <= 1'b1;
			end else if (cycle == TIME_BIT_H) begin // data half-bit
				data_out <= ~write_buffer[0];
				write_buffer <= write_buffer >> 1;
			end else if (cycle >= (TIME_BIT_R + TIME_BIT_H)) begin
				write_length <= write_length - 1'b1;
				cycle <= 0;
			end
		end

		STATE_WRITE_END: begin
			if (cycle == 0)
				data_out <= 1'b1;
			else if (cycle == TIME_SYNC_H)
				data_out <= 1'b0;
			else if (cycle == (TIME_SYNC_H + TIME_SYNC_L)) begin
				latch <= 1'b0; // Release
			end else if (cycle >= (TIME_SYNC_H + TIME_SYNC_L + TIME_SETTLE)) begin
				state <= STATE_IDLE;
                if (command_busy && payload_remaining != 0) begin
                    payload_remaining <= payload_remaining - 1'b1;
                    stage <= WRITE_PAYLOAD;
                end else if (command_busy && read_length == 0) begin
                    command_busy <= 0; CMD_DONE <= 1; stage <= READ_IDLE;
                    if (active_opcode == 8'h20) begin modes_attempted <= 0; MODES_VALID <= 0; lljs_modes <= 0; end
                end
                cycle <= 0;
            end
        end

        STATE_READ_START: begin
            if (cycle >= ((stage == READ_POLL || raw_active) ? TIME_POLL : RECEIVE_START_TIMEOUT)) begin
                // Discard this transaction and wait for both input lines to release.
                // Never repeatedly transmit into a device holding the bus low.
                state <= STATE_WAIT_RELEASE;
                stage <= READ_IDLE;
                cycle <= 0; count <= 0;
                packet_complete <= 0;
                latch <= 0; data_out <= 1;
                enable <= 0; LINK_FAULT <= 1; LAST_FAULT_REASON <= 2'd1;
                lljs_type <= 0; lljs_modes <= 0; lljs_buttons <= 0;
                modes_attempted <= 0; MODES_VALID <= 0;
                lljs_analog <= 72'h080000808080808080;
            end else if (cycle >= TIME_SETTLE && ~is_latched) begin // Just a busy wait/poll/blip
				cycle <= 0;
				if (stage == READ_POLL) begin // Poll processing gets its own budget.
                    stage <= WRITE_STATUS; transaction_timer <= 0;
                end
				state <= STATE_IDLE;
			end else if (count >= 'd10) begin // Allows for latch to be seen if both are released together
				cycle <= 'd10;
				read_bit <= 3'h0;
				state <= STATE_READ;
			end else if (cycle >= TIME_LEADIN && data_in) begin // If we get data high it means we're reading
				count <= count + 1'b1;
			end
		end

        STATE_WAIT_RELEASE: begin
            latch <= 0; data_out <= 1;
            if (is_latched || !data_in) cycle <= 0;
            else if (cycle >= TIME_SETTLE) begin
                state <= STATE_IDLE; stage <= READ_IDLE;
                cycle <= 0; count <= 0;
                poll_offset <= 0; poll_offset_latch <= 0;
                poll_time <= TIME_POLL;
                sync_counter <= TIME_POLL; poll_counter <= 0;
            end
        end

		// Allow the actual byte-sync edge to arrive before falling back.
		// Ignore early edges belonging to the preceding final data bit.
		STATE_READ_WAIT: begin // the space between the bytes
			if (cycle > ((TIME_SYNC_H + TIME_SYNC_L) * 2) ||
				((cycle > TIME_SYNC_H) && ~old_data && data_in)) begin // Re align during wait if needed
				cycle <= 0;
				read_bit <= 3'h0;
				if (read_byte >= read_length) state <= STATE_READ_END; else state <= STATE_READ;
			end
		end

		STATE_READ: begin
			if (~is_latched) begin // Accounts from random timing errors or unexpected events
				cycle <= 0;
				state <= STATE_IDLE;
			end else if (read_byte >= read_length || read_byte >= 13) begin
                state <= STATE_READ_END; cycle <= 0;
            end else if (cycle == (TIME_BIT_H + (TIME_BIT_R >> 1))) begin // latch in the middle of the data window
				read_buffer[read_byte][read_bit] <= ~data_in;
				read_bit <= read_bit + 1'b1;
			end else if (cycle >= TIME_BIT_H + TIME_BIT_R) begin
				cycle <= 0;
				if (read_bit == 3'h0) begin // This relies on overflow behavior
					if (read_byte == 0) begin
						if (stage == READ_STATUS) begin
							pending_type <= read_buffer[0];
						end
					end else if (read_byte == 'd12 && stage == READ_STATUS) begin
                        packet_complete <= 1;
						

						
					end
					poll_offset_latch <= poll_offset < (21'h1fffff - TIME_BUFFER) ? poll_offset + TIME_BUFFER : 21'h1fffff;
					read_byte <= read_byte + 1'd1;
                    if (!raw_active && read_byte == 0 && stage != READ_MODES && protocol_error(read_buffer[0])) read_length <= 1;
					state <= STATE_READ_WAIT;
				end
			end
		end
		/*
		#define DPAD_UP      0x04    00000100
		#define DPAD_DOWN    0x08    00001000
		#define DPAD_LEFT    0x10    00010000  
		#define DPAD_RIGHT   0x20    00100000

		#define DPAD_UPLEFT        0x14
		#define DPAD_DOWNLEFT    0x18
		#define DPAD_UPRIGHT    0x24
		#define DPAD_DOWNRIGHT    0x28
		#define DPAD_REST    0xff
		*/

		STATE_READ_END: begin
			// latch data to correct registers based on stage
			if (cycle >= TIME_WAIT) begin // bliss box holds the line low for about 3us after reply
                packet_complete <= 0;
                stage <= READ_IDLE;
                // Publish type, buttons and all axes together after a complete packet.
                if (stage == READ_STATUS && packet_complete && pending_type != 0 && !protocol_error(pending_type)) begin
                    STATUS_UPDATE <= 1;
                    repoll_pending <= IMMEDIATE_REPOLL;
                    TYPE_CHANGED <= STATUS_VALID && pending_type != lljs_type;
                    command_slot <= 1;
                    lljs_type <= pending_type;
                    lljs_buttons <= pending_buttons;
                    lljs_analog <= pending_analog;
                    if (MODES_VALID && pending_type == lljs_type && lljs_modes[7]) begin
                        lljs_buttons[27] <= pending_buttons[27] | (pending_analog[15:8] < 50);
                        lljs_buttons[26] <= pending_buttons[26] | (pending_analog[15:8] > 200);
                        lljs_buttons[25] <= pending_buttons[25] | (pending_analog[7:0] < 50);
                        lljs_buttons[24] <= pending_buttons[24] | (pending_analog[7:0] > 200);
                    end
                    // Both manual and automatic mode reads belong to this controller ID.
                    if (pending_type != lljs_type || (AUTO_MODES && !modes_attempted)) begin
                        lljs_modes <= 0; MODES_VALID <= 0;
                        if (AUTO_MODES) begin
                            stage <= WRITE_MODES; modes_attempted <= 1; transaction_timer <= 0;
                        end
                    end
                end
                if (stage == READ_STATUS && ((read_byte == 1 && protocol_error(read_buffer[0])) || (packet_complete && pending_type == 0))) begin
                    LINK_FAULT <= 1; LAST_FAULT_REASON <= 2'd2; enable <= 0; lljs_type <= 0; lljs_buttons <= 0;
                    lljs_analog <= 72'h080000808080808080;
                    lljs_modes <= 0; MODES_VALID <= 0; modes_attempted <= 0;
                end
                if ((stage == READ_MODES || (command_busy && active_opcode == 8'h21)) && read_byte == 1) begin
                    if (!protocol_error(read_buffer[0])) begin
                        lljs_modes <= read_buffer[0]; MODES_VALID <= 1;
                    end else begin lljs_modes <= 0; MODES_VALID <= 0; end
                end
                if (command_busy) begin
                    CMD_DONE <= 1; command_busy <= 0;
                    CMD_REPLY_LENGTH <= read_byte;
                    for (integer n=0; n<13; n=n+1)
                        if (n < read_byte) CMD_REPLY[n*8 +: 8] <= read_buffer[n];
                    if (!raw_active && read_byte == 1 && protocol_error(read_buffer[0])) CMD_ERROR <= read_buffer[0];
                end
                cycle <= 0;
                state <= STATE_IDLE;
			end
		end

		default: begin
			cycle <= 0;
			count <= 0;
			stage <= READ_IDLE;
			state <= STATE_IDLE;
		end
    endcase
    end else begin
        // ENABLE low resets only this instance; reuse it for per-port rediscovery.
        // Intentional disable is not a communication fault.
        STATUS_UPDATE <= 0; TYPE_CHANGED <= 0; LINK_FAULT <= 0; LAST_FAULT_REASON <= 0;
        // ENABLE low resets transaction/synchronization state deterministically.
        repoll_pending <= 0;
        modes_attempted <= 0; MODES_VALID <= 0; command_busy <= 0; command_slot <= 0;
        raw_selected <= 0; payload_remaining <= 0; active_opcode <= 0; transaction_timer <= 0;
        CMD_DONE <= 0; CMD_ERROR <= 0; CMD_REPLY <= 0; CMD_REPLY_LENGTH <= 0;
        pending_type <= 0;   packet_complete <= 0;
        cycle <= 0; count <= 0; poll_offset <= 0; poll_counter <= 0;
        poll_offset_latch <= 0; sync_counter <= 0; poll_time <= TIME_POLL;
        write_buffer <= 0; write_length <= 0;
        read_bit <= 0; read_byte <= 0; read_length <= 0;
        is_latched <= 0; data_in <= 1; old_data <= 1; data_out <= 1;
        old_sync <= 0; new_sync <= 0;
		latch <= 1'b0;
		enable <= 1'b0;
		lljs_analog <= 0;
		lljs_buttons <= 0;
		lljs_modes <= 0;
		lljs_type <= 0;
		state <= STATE_IDLE;
		stage <= READ_IDLE;
	end
end

endmodule

