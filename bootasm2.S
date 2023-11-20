# This code is linked to assume a starting address of 0x7C00 which is where the BIOS
# will load a boot segment.

.code16                         # Assemble for 16-bit mode
.globl start
start:
    jmp     real_start

# Write to the console using BIOS.
# 
# Input: SI contains the address of the null-terminated string to be displayed

cons_write:
    movb    $0x0e, %ah           # 0x0e is the INT 10h BIOS call to output the value contained in AL to screen

cons_write_rpt:
    movb    (%si), %al          # Load the byte at the location contained in the SI register into AL   
    inc     %si                 # Add 1 to the value in SI
    cmp     $0, %al             # Compare the value in AL with 0
    jz      cons_write_done     # If it is zero, then we are done
    int     $0x10               # Output the character in AL to the screen
    jmp     cons_write_rpt      # and continue

cons_write_done:                # Something that is called will never return 
    ret                         # until a 'ret' instruction is encountered.  Labels do 
                                # not give a program any structure.  They just give a 
                                # memory location a name that we can use in our code. 

cons_write_crlf:
    movb    $0x0e, %ah          # Output CR
    movb    $0x0d, %al
    int     $0x10
    movb    $0x0a, %al          # Output LF
    int     $0x10
    ret

cons_writeline:
    call    cons_write
    call    cons_write_crlf
    ret    
    
disk_address_packet:
    .byte   0x10
    .byte   0
    .word   0
    .long   0
    .long   0
    .long   0

read_failed:
    # Handle the read failure here. You can print an error message or loop indefinitely.
    # For simplicity, I'm making it loop indefinitely here.
    jmp     read_failed


real_start:
    movb    %dl, (boot_device) # Boot device number is passed in DL from BIOS. Save it here since DL might get trashed

    movw    $boot_message, %si  # Display our boot message
    call    cons_writeline

    movw    $booted_from_msg, %si
    call    cons_write

    movb    (boot_device), %dl
    cmp     $0x80, %dl
    jge     harddrive
    movw    $fd, %si

    jmp     device_name

harddrive:
    movw    $hd, %si

device_name:
    call    cons_writeline

    call    cons_write_crlf     # Add a newline

    call    input_prompts       # Asks for inputs from user

    call    cons_write_crlf     # Add a newline

    # Read the sector 0 into memory at 0xD000
    call    read_sector

    # Display contents of the sector
    call    display_sector

    jmp     endless_loop    


finish:
    call    cons_writeline

endless_loop:                   # Loop forever more
    jmp     endless_loop    


# Displays the current offset
display_offset:
    push    %cx                 # Save CX register
    mov     %ch, %al            # Move the high byte of CX into AL
    call    display_byte_hex    # Display the high byte
    mov     %cl, %al            # Move the low byte of CX into AL
    call    display_byte_hex    # Display the low byte
    pop     %cx                 # Restore CX register
    call    print_space         # Print a space character
    ret

input_prompts:
    call    ask_starting_sector

    call    cons_write_crlf     # Add a newline

    call    ask_num_of_sectors
    

    movb    $0, (%bx)   # Null-terminate the input buffer after the last digit

    call    cons_write_crlf     # Add a newline

    call    read_sector
    call    display_sector

ask_starting_sector:
    movw    $input_buffer, %bx   # Point BX to the start of the input buffer

    xor     %cx, %cx             # Clear cl register to use for counting characters

    movw    $sector_input_prompt, %si
    call    cons_write           # Display the "Enter sector number to read: " message
    

    call    inputs_handling  # Handles inputs

    call    starting_sector_conversion      # Convert the input to a number

    movb    $0, (%bx)   # Null-terminate the input buffer after the last digit

    ret

ask_num_of_sectors:

    movw    $num_sector_buffer, %bx   # Point BX to the start of the input buffer

    xor     %cx, %cx                    # Clear cl register to use for counting characters

    movw    $num_of_sectors_prompt, %si
    call    cons_write      

    call    inputs_handling

    call    convert_num_of_sectors

    movb    $0, (%bx)   # Null-terminate the input buffer after the last digit
    ret
    

inputs_handling:
    movb    $0x00, %ah      # Function 00h: Wait for a keypress
    int     $0x16           # Call BIOS keyboard interrupt
    

    # Check if 'Enter' key is presed (0x0D)
    cmpb    $0x0D, %al
    je      finish_sector_to_read

    # Check if 'Backspace' key is pressed (0x08)
    cmpb    $0x08, %al
    je      backspace_handling

    # Check if the character is a digit
    cmp     $'0', %al               # Check if the character is a digit lower than '0'
    jl      inputs_handling         # If so, wait for another character
    cmp     $'9', %al               # Check if the character is a digit higher than '9'
    jg      inputs_handling         # If so, wait for another character

    # Check if 4 characters have been entered
    cmp     $4, %cx
    jge     inputs_handling         # If so, wait for enter or backspace

    # Echo the character to the screen
    movb    $0x0E, %ah              # Function 0eh: Write character in AL to screen
    int     $0x10                   # Call BIOS video interrupt

    # Store the character in the buffer
    movb    %al, (%bx)              # Store the character in the buffer
    inc     %bx                     # Increment the buffer pointer
    inc     %cx                     # Increment the counter

    jmp     inputs_handling

backspace_handling:
    # Check if at the start of the buffer
    cmp     $input_buffer, %bx
    je      inputs_handling         # If at start, no backspace handling

    cmp $num_sector_buffer, %bx
    je      inputs_handling         # If at start, no backspace handling

    # Move the cursor back
    movb    $0x08, %al              # Load backspace character into AL
    movb    $0x0E, %ah              # Teletype output function
    int     $0x10                   # Output backspace

    # Print space to overwrite the character
    movb    $0x20, %al              # Load space character into AL
    int     $0x10                   # Output space

    # Move cursor back again after overwriting with space
    movb    $0x08, %al              # Load backspace character into AL
    int     $0x10                   # Output backspace again to go back to original position

    # Move the buffer pointer back
    dec     %bx                     # Decrement the buffer pointer
    dec     %cx                     # Decrement the counter
    movb    $0, (%bx)               # Null-terminate the string at the new end
    jmp     inputs_handling

finish_sector_to_read:
    ret

convert_num_of_sectors:
    movw    $num_sector_buffer, %si # Point SI to the start of the input buffer

    xorl    %eax, %eax              # Clear EAX register to use for conversion
    xorl    %ecx, %ecx              # Clear ECX register to use for conversion

    call    input_conversion_loop
    movl    %eax, num_of_sectors    # Move the sector number to num_of_sectors

    # If num_of_sectors is 0, call invalid_sector
    cmp     $0, num_of_sectors
    je      invalid_sector



starting_sector_conversion:
    movw    $input_buffer, %si   # Point SI to the start of the input buffer

    xorl    %eax, %eax           # Clear EAX register to use for conversion
    xorl    %ecx, %ecx           # Clear ECX register to use for conversion

    call    input_conversion_loop
    movl    %eax, starting_sector           # Move the sector number to starting_sector

input_conversion_loop:
    movb    (%si), %cl           # Move the first character to CL
    inc     %si                  # Increment SI
    testb   %cl, %cl             # Check if the character is NULL
    jz      sector_conversion_done # If so, we are done

    subb    $'0', %cl            # Convert the character to a number
    imull   $10, %eax            # Multiply the current number by 10
    addl    %ecx, %eax           # Add the current number to the total
    jmp     input_conversion_loop

sector_conversion_done:
    ret

# Output the 16-bit value in BX to the screen has a 4 digit hex value	
#
# Input:  BX = Value to output	

HexChars:	.ascii "0123456789ABCDEF"

# Output the value passed on the stack to the screen using the specified base
#

#define     number      6
#define     base        4

#define     endofstring -2

cons_write_number:
    pushw   %bp                 # Save existing frame pointer
    movw    %sp, %bp            # Setup our frame pointer
    subw    $18, %sp            # Reserve space for our string buffer
    pushw   %ax                 # Save the registers we will trash
    pushw   %bx
    pushw   %cx
    pushw   %dx
    pushw   %si
    pushw   %di

    movw    %bp, %si
    subw    $3, %si
    movb    $0, endofstring(%bp)    # Insert end of string indicator (0)    
    movw    number(%bp), %ax
	
getdigit:
	xor		%dx, %dx                # Divide number by base
	movw	base(%bp), %cx
	div		%cx
    movw    %dx, %di                # Convert remainder to hex character
    movb    HexChars(%di), %dl      # and stpre in buffer
	movb	%dl, (%si)
	dec		%si
	cmpw	$0, %ax                 # Have we extracted all digits?
	jne		getdigit
	inc		%si
	call	cons_write              # Output the string

    popw    %di                     # Restore the registers
    popw    %si
    popw    %dx
    popw    %cx
    popw    %bx
    popw    %ax
    movw    %bp, %sp                # Delete the local variables
    popw    %bp
    ret     $4                      # Return, removing paramters from stack

display_sector_number:
    call    cons_write_crlf
    movw    $display_contents_of_sector, %si
    call    cons_write
    movw    starting_sector, %ax
    push    %ax
    pushw   $10
    call    cons_write_number
    call    cons_write_crlf
    ret

read_sector:
    movb    $0x10, %ah                  # Reset disk system

    movw    $disk_address_packet, %si   # Point SI to the disk address packet
    movw    $1, 2(%si)                  # Read one sector (count = 1
    movw    $0xD000, 4(%si)                # LBAhi = 0

    movl    starting_sector, %eax
    movl    %eax, 8(%si)                # LBA = starting_sector

    movb    $0x42, %ah                    # Read disk sectors

    int     $0x13
    jc      read_failed

    ret

# Routine to wait for Enter key press
wait_for_enter:
    call    cons_write_crlf     # Add a newline
    movw    $continue_prompt, %si
    call    cons_writeline      # Display the "Press Enter to continue" message
    call    cons_write_crlf     # Add a newline
    movb    $0x00, %ah          # Function 00h: Wait for a keypress
    int     $0x16               # Call BIOS keyboard interrupt
    cmpb    $0x0D, %al          # Compare AL with the Enter key ASCII code
    jnz     wait_for_enter      # If not Enter, wait again
    ret

# Modify the display_sector routine to call wait_for_enter every 16 lines
display_sector:
    call    display_sector_number
    movw    $0xD000, %si        # Starting address of the sector
    movw    $0x0000, %cx        # Offset counter
    movw    %si, %di            # DI will be used to remember the start of the 16 bytes for ASCII display
    xor     %bx, %bx            # BX will count the number of lines displayed
    


display_outer_loop:
    call    display_offset      # Display the current offset
    movb    $0x10, %bh          # Number of bytes to display per line

display_inner_loop:
    movb    (%si), %al
    call    display_byte_hex   # Display the current byte in hex
    call    print_space        # Print a space character
    inc     %si                # Point to the next byte
    dec     %bh                # Decrement the byte counter for this line
    jz      new_line           # If we've displayed 16 bytes, move to a new line

    jmp     display_inner_loop

new_line:
    movw    %di, %si             # Point SI to the start of the 16 bytes we've just displayed
    call    display_ascii        # Display ASCII values
    call    cons_write_crlf      # Move to a new line
    add     $0x10, %di           # Move DI to next 16 bytes
    add     $0x10, %cx           # Increase the offset by 16
    inc     %bx                  # Increment line counter
    cmp     $0x10, %bx           # Check if 16 lines have been displayed
    je      prompt_once
    cmp     $0x20, %bx           # Check if 32 lines have been displayed
    je      all_sectors_displayed  # If yes, go to end message
    jmp     display_outer_loop

prompt_once:
    push    %si                  # Save SI, DI, and CX before the prompt
    push    %di
    push    %cx
    call    wait_for_enter      # Call the routine to prompt user
    pop     %cx                 # Restore SI, DI, and CX after the prompt
    pop     %di
    pop     %si
    jmp     display_outer_loop         # Continue with the display after prompt

all_sectors_displayed:          # ADD CHECK FOR IF THE NUMBER OF SECTORS HAS BEEN DISPLAYED
    movl    num_of_sectors, %ecx
    subl    $1, %ecx
    movl    %ecx, num_of_sectors
    cmp     $0, num_of_sectors
    jne     move_on

    call    done_display_sector

move_on:
    addl    $1, starting_sector

    call    wait_for_enter

    call    read_sector
    call    display_sector
    jmp     display_outer_loop
    
    
done_display_sector:
    movw   $sector_finished_prompt, %si
    call   cons_writeline
    jmp    input_prompts


# Displays ASCII representation of the byte
display_ascii:
    movb    $0x10, %bh         # Number of bytes to display

display_ascii_loop:
    movb    (%si), %al
    
    # Check for specific non-printable characters
    cmp     $0x00, %al          # Check for NULL character
    je      non_printable
    cmp     $0x1F, %al          # Check for control characters
    jbe     non_printable       # Jump if AL is below or equal to 0x1F

    # Print the ASCII character
    movb    %al, %ah
    movb    $0x0e, %ah
    int     $0x10
    jmp     ascii_done

non_printable:
    # Display an underscore for non-printable characters
    movb    $0x5F, %al         # ASCII for underscore
    movb    %al, %ah
    movb    $0x0e, %ah
    int     $0x10

ascii_done:
    inc     %si                # Move to the next byte
    dec     %bh                # Decrement the byte counter
    jz      done_ascii         # If we've displayed 16 characters, we are done
    jmp     display_ascii_loop

done_ascii:
    ret

# Displays a byte in hexadecimal
display_byte_hex:
    pusha                              # Save all registers

    andb    $0xF0, %al                 # Get high nibble
    shr     $4, %al
    call    display_nibble_hex

    popa                               # Restore registers
    andb    $0x0F, %al                 # Get low nibble
    call    display_nibble_hex

    ret

# Displays a nibble (4 bits) in hexadecimal
display_nibble_hex:
    cmp     $0x0A, %al
    jl      is_digit
    add     $0x37, %al                 # Convert A-F to 'A'-'F'
    jmp     print_char

is_digit:
    add     $0x30, %al                 # Convert 0-9 to '0'-'9'

print_char:
    movb    %al, %ah
    movb    $0x0e, %ah
    int     $0x10
    ret

print_space:
    movb    $0x20, %al
    call    print_char
    ret

invalid_sector:
    movw    $invalid_sector_prompt, %si
    call    cons_write_crlf
    call    cons_writeline
    jmp     input_prompts

# Program data

boot_device:
    .byte   0

display_contents_of_sector:
    .string "Displaying contents of sector: "

boot_message:     
    .string "Boot Loader Stage 2 loaded"             
booted_from_msg:
    .string "Booting from "
fd: .string "floppy disk"
hd: .string "hard drive"

sector_input_prompt:
    .string "Enter sector number to read: "

num_of_sectors_prompt:
    .string "Enter number of sectors to read: "

continue_prompt:
    .string "Press Enter to continue"

sector_finished_prompt:
    .string "Fully read sector successfully!"

invalid_sector_prompt:
    .string "Invalid sector number!"

num_sector_buffer:
    .space  5                    # Reserve 5 bytes for number of sector buffer

input_buffer:
    .space  5                    # Reserve 5 bytes for input buffer

num_of_sectors:
    .long   0

starting_sector:
    .long   0