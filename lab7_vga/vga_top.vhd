LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
USE IEEE.std_logic_unsigned.ALL;

ENTITY vga_top IS
    PORT (
        CLK_I : IN STD_LOGIC; --input clk from zybo
        sw : IN STD_LOGIC_VECTOR (3 DOWNTO 0);
        btn : IN std_logic_vector(3 downto 0);
        VGA_HS_O : OUT STD_LOGIC;
        VGA_VS_O : OUT STD_LOGIC;
        VGA_r : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);  
        VGA_b : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
        VGA_g : OUT STD_LOGIC_VECTOR (3 DOWNTO 0)
    );
END vga_top;

ARCHITECTURE Behavioral OF vga_top IS

    COMPONENT clk_wiz_0
        PORT (-- Clock in ports
            CLK_IN1 : IN STD_LOGIC;
            -- Clock out ports
            CLK_OUT1 : OUT STD_LOGIC
        );
    END COMPONENT;

    --Sync Generation constants
    --***1920x1080@60Hz***--  Requires 148.5 MHz clock
    CONSTANT FRAME_WIDTH : NATURAL := 1920;
    CONSTANT FRAME_HEIGHT : NATURAL := 1080;

    CONSTANT H_FP : NATURAL := 88; --H front porch width (pixels)
    CONSTANT H_PW : NATURAL := 44; --H sync pulse width (pixels)
    CONSTANT H_MAX : NATURAL := 2200; --H total period (pixels)

    CONSTANT V_FP : NATURAL := 4; --V front porch width (lines)
    CONSTANT V_PW : NATURAL := 5; --V sync pulse width (lines)
    CONSTANT V_MAX : NATURAL := 1125; --V total period (lines)

    CONSTANT H_POL : STD_LOGIC := '1';
    CONSTANT V_POL : STD_LOGIC := '1';

    CONSTANT FirstH_Q : NATURAL := (FRAME_WIDTH/3);
    CONSTANT SecondH_Q : NATURAL := ((2 * FRAME_WIDTH)/3);
    CONSTANT ThirdH_Q : NATURAL := FRAME_WIDTH;
    CONSTANT Eighths : NATURAL := (FRAME_WIDTH/8);

    SIGNAL pxl_clk : STD_LOGIC;
    SIGNAL active : STD_LOGIC;

    SIGNAL h_cntr_reg : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
    SIGNAL v_cntr_reg : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
    SIGNAL h_comp : integer; --unsigned(11 DOWNTO 0) := (OTHERS => '0');
    SIGNAL v_comp : integer; --unsigned(11 DOWNTO 0) := (OTHERS => '0');

    SIGNAL vga_red_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := (OTHERS => '0');
    SIGNAL vga_green_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := (OTHERS => '0');
    SIGNAL vga_blue_reg : STD_LOGIC_VECTOR(3 DOWNTO 0) := (OTHERS => '0');

    SIGNAL vga_red : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL vga_green : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL vga_blue : STD_LOGIC_VECTOR(3 DOWNTO 0);

    --bitmap signals for ball
    TYPE rom_type IS ARRAY (0 TO 19) OF STD_LOGIC_VECTOR(19 DOWNTO 0);

    -- ROM definition
    CONSTANT BALL_ROM : rom_type :=
    (
    "00000111111111100000",
    "00001111111111110000",
    "00111111111111111100",
    "00111111111111111100",
    "01111111111111111110",
    "11111111111111111111",
    "11111111111111111111",
    "11111111111111111111",
    "11111111111111111111",
    "11111111111111111111",
    "11111111111111111111",
    "11111111111111111111",
    "11111111111111111111",
    "11111111111111111111",
    "11111111111111111111",
    "01111111111111111110",
    "00111111111111111100",
    "00111111111111111100",
    "00001111111111110000",
    "00000111111111100000"
    );
 
    constant BOX_X_INIT : std_logic_vector(14 downto 0) := (OTHERS => '0');
    constant BOX_Y_INIT : std_logic_vector(14 downto 0) := (OTHERS => '0'); --400
    constant BOX_X_MIN : natural := 0;
    constant BOX_Y_MIN : natural := 0;
    constant BOX_WIDTH : natural := 20;
    constant BOX_X_MAX : natural := (FRAME_WIDTH - BOX_WIDTH);
    constant BOX_Y_MAX : natural := (FRAME_HEIGHT - BOX_WIDTH);
    constant BOX_CLK_DIV : natural := 1_000_000;

    
    signal h_sync_reg : std_logic := not(H_POL);
    signal v_sync_reg : std_logic := not(V_POL);
    
    signal h_sync_dly_reg : std_logic := not(H_POL);
    signal v_sync_dly_reg : std_logic :=  not(V_POL);

    signal box_x_reg : std_logic_vector(14 downto 0) := BOX_X_INIT;
    signal box_x_dir : std_logic := '1';
    signal box_y_reg : std_logic_vector(14 downto 0) := BOX_Y_INIT;
    signal box_y_dir : std_logic := '1';
    signal box_cntr_reg : std_logic_vector(24 downto 0) := (others =>'0');

    signal update_box : std_logic;
    signal pixel_in_box : std_logic;
    signal ball_point : std_logic; --_vector(5 downto 0);   --needs to hold value of 20 or less

BEGIN
    --clk wizard generated by IP catalog: sets clk to 148.5Mhz
    clk_div_inst : clk_wiz_0
    PORT MAP
    (-- Clock in ports
        CLK_IN1 => CLK_I,
        -- Clock out ports
        CLK_OUT1 => pxl_clk);
        
 
    ------------------------------------------------------
    -- SYNC GENERATION                 
    ------------------------------------------------------
    --HORIZONTAL COUNTER: goes to H_max 
    PROCESS (pxl_clk)
    BEGIN
        IF (rising_edge(pxl_clk)) THEN
            IF (h_cntr_reg = (H_MAX - 1)) THEN
                h_cntr_reg <= (OTHERS => '0');
            ELSE
                h_cntr_reg <= h_cntr_reg + 1;
            END IF;
        END IF;
    END PROCESS;

    --VERTICAL COUNTER: goes to V_max 
    PROCESS (pxl_clk)
    BEGIN
        IF (rising_edge(pxl_clk)) THEN
            IF ((h_cntr_reg = (H_MAX - 1)) AND (v_cntr_reg = (V_MAX - 1))) THEN
                v_cntr_reg <= (OTHERS => '0');
            ELSIF (h_cntr_reg = (H_MAX - 1)) THEN
                v_cntr_reg <= v_cntr_reg + 1;
            END IF;
        END IF;
    END PROCESS;

    --CHECK FOR H_SYNC TO GO ACTIVE 
    PROCESS (pxl_clk)
    BEGIN
        IF (rising_edge(pxl_clk)) THEN
            IF (h_cntr_reg >= (H_FP + FRAME_WIDTH - 1)) AND (h_cntr_reg < (H_FP + FRAME_WIDTH + H_PW - 1)) THEN --IF reached the beginning of the back porch, toggle the polarization logic
                h_sync_reg <= H_POL;
            ELSE
                h_sync_reg <= NOT(H_POL);
            END IF;
        END IF;
    END PROCESS;

    --
    PROCESS (pxl_clk)
    BEGIN
        IF (rising_edge(pxl_clk)) THEN
            IF (v_cntr_reg >= (V_FP + FRAME_HEIGHT - 1)) AND (v_cntr_reg < (V_FP + FRAME_HEIGHT + V_PW - 1)) THEN --change the toggle logic of vsync
                v_sync_reg <= V_POL;
            ELSE
                v_sync_reg <= NOT(V_POL);
            END IF;
        END IF;
    END PROCESS;

    active <= '1' WHEN ((h_cntr_reg < FRAME_WIDTH) AND (v_cntr_reg < FRAME_HEIGHT)) ELSE --active when not at limits
        '0';

    --cont signals for integer comparison in the case statement
    h_comp <= to_integer(unsigned(h_cntr_reg));
    v_comp <= to_integer(unsigned(h_cntr_reg));
    --H_FP
    --VGA controller
    PROCESS (active, h_comp, v_comp, btn)
    BEGIN
        IF active = '1' THEN
            CASE sw IS
                WHEN "0000" => --OFF
                    vga_red <= (OTHERS => '0');
                    vga_green <= (OTHERS => '0');
                    vga_blue <= (OTHERS => '0');
                WHEN "0001" => --SOLID RED
                    VGA_red <= (OTHERS => '1');
                    VGA_blue <= (OTHERS => '0');
                    VGA_green <= (OTHERS => '0');
                WHEN "0010" => --SOLID GREEN
                    VGA_red <= (OTHERS => '0');
                    VGA_blue <= (OTHERS => '0');
                    VGA_green <= (OTHERS => '1');
                WHEN "0100" => --THREE REGIONS => RGB
                    IF (h_comp >= 0 AND h_comp < FirstH_Q) THEN
                        VGA_red <= (OTHERS => '1');
                        VGA_blue <= (OTHERS => '0');
                        VGA_green <= (OTHERS => '0');
                    ELSIF (h_comp >= FirstH_Q AND h_comp < SecondH_Q) THEN
                        VGA_red <= (OTHERS => '0');
                        VGA_blue <= (OTHERS => '0');
                        VGA_green <= (OTHERS => '1');
                    ELSIF (h_comp >= SecondH_Q AND h_comp < (ThirdH_Q)) THEN
                        VGA_red <= (OTHERS => '0');
                        VGA_blue <= (OTHERS => '1');
                        VGA_green <= (OTHERS => '0');
                    END IF;
                WHEN "0101" => --8 REGIONS WITH DIFFERENT COLORS
                    IF (h_comp >= 0 AND h_comp < Eighths) THEN
                        VGA_red <= (OTHERS => '1');
                        VGA_blue <= (OTHERS => '0');
                        VGA_green <= (OTHERS => '1');
                    ELSIF (h_comp >= Eighths AND h_comp < 2 * Eighths) THEN
                        VGA_red <= (OTHERS => '1');
                        VGA_blue <= (OTHERS => '1');
                        VGA_green <= (OTHERS => '0');
                    ELSIF (h_comp >= 2 * Eighths AND h_comp < 3 * Eighths) THEN
                        VGA_red <= (OTHERS => '1');
                        VGA_blue <= (OTHERS => '0');
                        VGA_green <= (OTHERS => '1');
                    ELSIF (h_comp >= 3 * Eighths AND h_comp < 4 * Eighths) THEN
                        VGA_red <= (OTHERS => '0');
                        VGA_blue <= (OTHERS => '1');
                        VGA_green <= (OTHERS => '1');
                    ELSIF (h_comp >= 4 * Eighths AND h_comp < 5 * Eighths) THEN
                        VGA_red <= (OTHERS => '1');
                        VGA_blue <= (OTHERS => '1');
                        VGA_green <= (OTHERS => '0');
                    ELSIF (h_comp >= 5 * Eighths AND h_comp < 6 * Eighths) THEN
                        VGA_red <= (OTHERS => '1');
                        VGA_blue <= (OTHERS => '1');
                        VGA_green <= (OTHERS => '1');
                    ELSIF (h_comp >= 6 * Eighths AND h_comp < 7 * Eighths) THEN
                        VGA_red <= (OTHERS => '1');
                        VGA_blue <= (OTHERS => '0');
                        VGA_green <= (OTHERS => '1');
                    ELSIF (h_comp >= 7 * Eighths AND h_comp < ((8 * Eighths))) THEN
                        VGA_red <= (OTHERS => '1');
                        VGA_blue <= (OTHERS => '0');
                        VGA_green <= (OTHERS => '1');
                    END IF;
                WHEN "0110" => --8 SHADES OF GRAY
                    IF (h_comp >= 0 AND h_comp < 240) THEN
                        -- white
                        vga_red <= (OTHERS => '1');
                        vga_green <= (OTHERS => '1');
                        vga_blue <= (OTHERS => '1');
                    ELSIF (h_comp >= Eighths AND h_comp < 2 * eighths) THEN
                        vga_red <= "1110";
                        vga_green <= "1110";
                        vga_blue <= "1110";
                    ELSIF (h_comp >= 2 * eighths AND h_comp < 3 * eighths) THEN
                        vga_red <= "1100";
                        vga_green <= "1100";
                        vga_blue <= "1100";
                    ELSIF (h_comp >= 3 * eighths AND h_comp < 4 * eighths) THEN
                        vga_red <= "1010";
                        vga_green <= "1010";
                        vga_blue <= "1010";
                    ELSIF (h_comp >= 4 * eighths AND h_comp < 5 * eighths) THEN
                        vga_red <= "1000";
                        vga_green <= "1000";
                        vga_blue <= "1000";
                    ELSIF (h_comp >= 5 * eighths AND h_comp < 6 * eighths) THEN
                        vga_red <= "0110";
                        vga_green <= "0110";
                        vga_blue <= "0110";
                    ELSIF (h_comp >= 6 * eighths AND h_comp < 7 * eighths) THEN
                        vga_red <= "0010";
                        vga_green <= "0010";
                        vga_blue <= "0010";
                    ELSIF (h_comp >= 7 * eighths AND h_comp < (8 * eighths)) THEN
                        -- black
                        vga_red <= (OTHERS => '0');
                        vga_green <= (OTHERS => '0');
                        vga_blue <= (OTHERS => '0');
                    ELSE
                        vga_red <= (OTHERS => '0');
                        vga_green <= (OTHERS => '0');
                        vga_blue <= (OTHERS => '0');
                    END IF;
                WHEN "0111" => --CREATE DIFF HORZ STRIPES W/ COUNTER
                    CASE btn IS
                        WHEN "0000" => vga_red <= h_cntr_reg(3 DOWNTO 0);
                            vga_green <= h_cntr_reg(3 DOWNTO 0);
                            vga_blue <= h_cntr_reg(3 DOWNTO 0);
                        WHEN "0001" => vga_red <= h_cntr_reg(4 DOWNTO 1);
                            vga_green <= h_cntr_reg(4 DOWNTO 1);
                            vga_blue <= h_cntr_reg(4 DOWNTO 1);
                        WHEN "0010" => vga_red <= h_cntr_reg(5 DOWNTO 2);
                            vga_green <= h_cntr_reg(5 DOWNTO 2);
                            vga_blue <= h_cntr_reg(5 DOWNTO 2);
                        WHEN "0100" => vga_red <= h_cntr_reg(6 DOWNTO 3);
                            vga_green <= h_cntr_reg(6 DOWNTO 3);
                            vga_blue <= h_cntr_reg(6 DOWNTO 3);
                        WHEN "1000" => vga_red <= h_cntr_reg(11 DOWNTO 8);
                            vga_green <= h_cntr_reg(11 DOWNTO 8);
                            vga_blue <= h_cntr_reg(11 DOWNTO 8);
                        WHEN OTHERS =>
                            vga_red <= (OTHERS => '0');
                            vga_green <= (OTHERS => '0');
                            vga_blue <= (OTHERS => '0');
                    END CASE;
                WHEN "1000" => --CREATE DIFF vert STRIPES
                    CASE btn IS
                        WHEN "0000" => vga_red <= v_cntr_reg(3 DOWNTO 0);
                            vga_green <= v_cntr_reg(3 DOWNTO 0);
                            vga_blue <= v_cntr_reg(3 DOWNTO 0);
                        WHEN "0001" => vga_red <= v_cntr_reg(4 DOWNTO 1);
                            vga_green <= v_cntr_reg(4 DOWNTO 1);
                            vga_blue <= v_cntr_reg(4 DOWNTO 1);
                        WHEN "0010" => vga_red <= v_cntr_reg(5 DOWNTO 2);
                            vga_green <= v_cntr_reg(5 DOWNTO 2);
                            vga_blue <= v_cntr_reg(5 DOWNTO 2);
                        WHEN "0100" => vga_red <= v_cntr_reg(6 DOWNTO 3);
                            vga_green <= v_cntr_reg(6 DOWNTO 3);
                            vga_blue <= v_cntr_reg(6 DOWNTO 3);
                        WHEN "1000" => vga_red <= v_cntr_reg(11 DOWNTO 8);
                            vga_green <= v_cntr_reg(11 DOWNTO 8);
                            vga_blue <= v_cntr_reg(11 DOWNTO 8);
                        WHEN OTHERS =>
                            vga_red <= (OTHERS => '0');
                            vga_green <= (OTHERS => '0');
                            vga_blue <= (OTHERS => '0');
                    END CASE;
                WHEN "1001" =>
                    -- create different size checker board pattern
                    CASE btn IS
                        WHEN "0000" =>
                            vga_red <= (OTHERS => (v_cntr_reg(5) XOR h_cntr_reg(5)));
                            vga_green <= (OTHERS => (v_cntr_reg(5) XOR h_cntr_reg(5)));
                            vga_blue <= (OTHERS => (v_cntr_reg(5) XOR h_cntr_reg(5)));
                        WHEN "0001" =>
                            vga_red <= (OTHERS => (v_cntr_reg(6) XOR h_cntr_reg(6)));
                            vga_green <= (OTHERS => (v_cntr_reg(6) XOR h_cntr_reg(6)));
                            vga_blue <= (OTHERS => (v_cntr_reg(6) XOR h_cntr_reg(6)));
                        WHEN "0010" =>
                            vga_red <= (OTHERS => (v_cntr_reg(7) XOR h_cntr_reg(7)));
                            vga_green <= (OTHERS => (v_cntr_reg(7) XOR h_cntr_reg(7)));
                            vga_blue <= (OTHERS => (v_cntr_reg(7) XOR h_cntr_reg(7)));
                        WHEN "0100" =>
                            vga_red <= (OTHERS => (v_cntr_reg(8) XOR h_cntr_reg(8)));
                            vga_green <= (OTHERS => (v_cntr_reg(8) XOR h_cntr_reg(8)));
                            vga_blue <= (OTHERS => (v_cntr_reg(8) XOR h_cntr_reg(8)));
                        WHEN "1000" =>
                            vga_red <= (OTHERS => (v_cntr_reg(9) XOR h_cntr_reg(9)));
                            vga_green <= (OTHERS => (v_cntr_reg(9) XOR h_cntr_reg(9)));
                            vga_blue <= (OTHERS => (v_cntr_reg(9) XOR h_cntr_reg(9)));
                        WHEN OTHERS =>
                            vga_red <= (OTHERS => '0');
                            vga_green <= (OTHERS => '0');
                            vga_blue <= (OTHERS => '0');
                    END CASE;

                WHEN "1010" =>
                    -- create checkerboard with inner repeat pattern
                    CASE btn IS
                        WHEN "0000" =>
                            vga_red <= v_cntr_reg(6 DOWNTO 3) AND h_cntr_reg(6 DOWNTO 3);
                            vga_green <= v_cntr_reg(6 DOWNTO 3) AND h_cntr_reg(6 DOWNTO 3);
                            vga_blue <= v_cntr_reg(6 DOWNTO 3) AND h_cntr_reg(6 DOWNTO 3);
                        WHEN "0001" =>
                            vga_red <= v_cntr_reg(6 DOWNTO 3) OR h_cntr_reg(6 DOWNTO 3);
                            vga_green <= v_cntr_reg(6 DOWNTO 3) OR h_cntr_reg(6 DOWNTO 3);
                            vga_blue <= v_cntr_reg(6 DOWNTO 3) OR h_cntr_reg(6 DOWNTO 3);
                        WHEN "0010" =>
                            vga_red <= v_cntr_reg(6 DOWNTO 3) XOR h_cntr_reg(6 DOWNTO 3);
                            vga_green <= v_cntr_reg(6 DOWNTO 3) XOR h_cntr_reg(6 DOWNTO 3);
                            vga_blue <= v_cntr_reg(6 DOWNTO 3) XOR h_cntr_reg(6 DOWNTO 3);
                        WHEN "0100" =>
                            vga_red <= v_cntr_reg(7 DOWNTO 4) XOR h_cntr_reg(7 DOWNTO 4);
                            vga_green <= v_cntr_reg(7 DOWNTO 4) XOR h_cntr_reg(7 DOWNTO 4);
                            vga_blue <= v_cntr_reg(7 DOWNTO 4) XOR h_cntr_reg(7 DOWNTO 4);
                        WHEN "1000" =>
                            vga_red <= v_cntr_reg(8 DOWNTO 5) XOR h_cntr_reg(8 DOWNTO 5);
                            vga_green <= v_cntr_reg(8 DOWNTO 5) XOR h_cntr_reg(8 DOWNTO 5);
                            vga_blue <= v_cntr_reg(8 DOWNTO 5) XOR h_cntr_reg(8 DOWNTO 5);
                        WHEN OTHERS =>
                            vga_red <= (OTHERS => '0');
                            vga_green <= (OTHERS => '0');
                            vga_blue <= (OTHERS => '0');
                    END CASE;
                WHEN "1110" =>
                    -- show moving ball
                    IF pixel_in_box = '1' THEN
                        vga_red <= (OTHERS => '1');
                    ELSE
                        vga_red <= (OTHERS => '0');
                    END IF;
                WHEN OTHERS =>
                    VGA_red <= (OTHERS => '0');       
                    VGA_blue <= (OTHERS => '0');      
                    VGA_green <= (OTHERS => '0');     
            END CASE;
        ELSE
            VGA_red <= (OTHERS => '0');
            VGA_blue <= (OTHERS => '0');
            VGA_green <= (OTHERS => '0');
        END IF;
    END PROCESS;

    ------------------------------------------------------------------------
    --Ball Handling
    ------------------------------------------------------------------------
       --BAll position counter by axis
       process (pxl_clk)
       begin
         if (rising_edge(pxl_clk)) then
           if (update_box = '1') then
             if (box_x_dir = '1') then
               box_x_reg <= box_x_reg + 1;
             else
               box_x_reg <= box_x_reg - 1;
             end if;
             if (box_y_dir = '1') then
               box_y_reg <= box_y_reg + 1;
             else
               box_y_reg <= box_y_reg - 1;
             end if;
           end if;
         end if;
       end process;
        
       --setting directions based on where we are on the screen
       process (pxl_clk)
       begin
         if (rising_edge(pxl_clk)) then
           if (update_box = '1') then
             if ((box_x_dir = '1' and (box_x_reg = BOX_X_MAX - 1)) or (box_x_dir = '0' and (box_x_reg = BOX_X_MIN + 1))) then
               box_x_dir <= not(box_x_dir);
             end if;
             if ((box_y_dir = '1' and (box_y_reg = BOX_Y_MAX - 1)) or (box_y_dir = '0' and (box_y_reg = BOX_Y_MIN + 1))) then
               box_y_dir <= not(box_y_dir);
             end if;
           end if;
         end if;
       end process;
        
       --BALL clk counter
       process (pxl_clk)
       begin
         if (rising_edge(pxl_clk)) then
           if (box_cntr_reg = (BOX_CLK_DIV - 1)) then
             box_cntr_reg <= (others=>'0');
           else
             box_cntr_reg <= box_cntr_reg + 1;    
           end if;
         end if;
       end process;

       update_box <= '1' when box_cntr_reg = (BOX_CLK_DIV - 1) else
                       '0';
       ball_point <= BALL_ROM(conv_integer(v_cntr_reg(4 downto 0) - box_y_reg))(conv_integer(h_cntr_reg(4 downto 0) - box_x_reg)) when (((h_cntr_reg >= box_x_reg) and (h_cntr_reg < (box_x_reg + BOX_WIDTH))) and
        ((v_cntr_reg >= box_y_reg) and (v_cntr_reg < (box_y_reg + BOX_WIDTH)))) else
                '0';

       pixel_in_box <= ball_point when (((h_cntr_reg >= box_x_reg) and (h_cntr_reg < (box_x_reg + BOX_WIDTH))) and
                           ((v_cntr_reg >= box_y_reg) and (v_cntr_reg < (box_y_reg + BOX_WIDTH)))) else
                        '0';      

    --sync regs to outputs 
    PROCESS (pxl_clk)
    BEGIN
        IF (rising_edge(pxl_clk)) THEN
            v_sync_dly_reg <= v_sync_reg;
            h_sync_dly_reg <= h_sync_reg;
            VGA_red_reg <= VGA_red;
            VGA_green_reg <= VGA_green;
            VGA_blue_reg <= VGA_blue;
        END IF;
    END PROCESS;

    VGA_HS_O <= h_sync_dly_reg;
    VGA_VS_O <= v_sync_dly_reg;
    VGA_R <= VGA_red_reg;
    VGA_G <= VGA_green_reg;
    VGA_B <= VGA_blue_reg;

END ARCHITECTURE;          

--setup clk wiz
--setup PMOD files proj ( github folder => "hw" gets total viv proj and one created from lecture)