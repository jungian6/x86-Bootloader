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

    call    new_str      # Wait for Enter key press

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
    push    %cx             # Save CX register
    mov     %ch, %al        # Move the high byte of CX into AL
    call    display_byte_hex # Display the high byte
    mov     %cl, %al        # Move the low byte of CX into AL
    call    display_byte_hex # Display the low byte
    pop     %cx             # Restore CX register
    call    print_space     # Print a space character
    ret

sector_to_read:
    movw    $sector_to_read_prompt, %si
    call    cons_writeline      # Display the "Press Enter to continue" message
    movb    $0x00, %ah        # Function 00h: Wait for a keypress
    int     $0x16              # Call BIOS keyboard interrupt
    cmpb    $0x0D, %al        # Compare AL with the Enter key ASCII code
    jnz     sector_to_read     # If not Enter, wait again
    # Read the sector 0 into memory at 0xD000
    call    read_sector

    # Display contents of the sector
    call    display_sector

    jmp     endless_loop

new_str:
    # Point DX to the start of the buffer
    movw    %si, %bx

    xor     %cx, %cx        # Clear cl register to use for counting characters

    jmp    new_sector_to_read

new_sector_to_read:
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
    jl      new_sector_to_read      # If so, wait for another character
    cmp     $'9', %al               # Check if the character is a digit higher than '9'
    jg      new_sector_to_read      # If so, wait for another character

    # Check if 4 characters have been entered
    cmp     $4, %cx
    jge     new_sector_to_read      # If so, wait for enter or backspace

    # Echo the character to the screen
    movb    $0x0E, %ah              # Function 0eh: Write character in AL to screen
    int     $0x10                   # Call BIOS video interrupt

    # Store the character in the buffer
    movb    %al, (%bx)              # Store the character in the buffer
    inc     %bx                     # Increment the buffer pointer
    inc     %cx                     # Increment the counter

    jmp     new_sector_to_read

backspace_handling:
    # Check is at the start of the buffer
    cmp     %si, %bx
    je      new_sector_to_read      # If so, wait for another character

    # Move cursor back
    movb    $0x0E, %ah
    movb    $0x08, %al
    int     $0x10

    # Print space to erase the character
    movb    $0x20, %al
    int     $0x10

    # Move the buffer pointer back
    dec     %bx                     # Decrement the buffer pointer
    dec     %cl                     # Decrement the counter

finish_sector_to_read:
    ret

read_sector:
    movb    $0x10, %ah                  # Reset disk system
    int     $0x13

    # Set up the disk address packet to read sector 0
    movw    $0x1, disk_address_packet+2  # Number of sectors to read = 1
    movw    $0xD000, disk_address_packet+4 # Buffer address = 0xD000
    # xorl    %eax, %eax
    movl    $0x0, %eax
    movl    %eax, disk_address_packet+8   # LBA = 0


    movb    $0x42, %ah                    # Read disk sectors
    movb    (boot_device), %dl
    leaw    disk_address_packet, %si
    int     $0x13

    jc      read_failed
    ret

# Routine to wait for Enter key press
wait_for_enter:
    movw    $continue_prompt, %si
    call    cons_writeline      # Display the "Press Enter to continue" message
    movb    $0x00, %ah          # Function 00h: Wait for a keypress
    int     $0x16               # Call BIOS keyboard interrupt
    cmpb    $0x0D, %al          # Compare AL with the Enter key ASCII code
    jnz     wait_for_enter      # If not Enter, wait again
    ret

# Modify the display_sector routine to call wait_for_enter every 16 lines
display_sector:
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
    je      done_display_sector  # If yes, go to end message
    call    display_next

    # pusha                    # Save registers
    # call wait_for_enter      # Wait for Enter key press
    # popa                     # Restore registers
    # xor %bx, %bx             # Reset line counter after Enter is pressed

prompt_once:
    push    %si                  # Save SI, DI, and CX before the prompt
    push    %di
    push    %cx
    call    wait_for_enter      # Call the routine to prompt user
    pop     %cx                  # Restore SI, DI, and CX after the prompt
    pop     %di
    pop     %si
    jmp     display_next         # Continue with the display after prompt

display_next:
    cmp     $0x200, %cx          # Check if we've displayed all 512 bytes
    jz      done_display_sector
    jmp     display_outer_loop
    
done_display_sector:
    movw   $sector_finsihed_prompt, %si
    call   cons_writeline
    jmp    sector_to_read
    ret


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


# Program data

boot_device:
    .byte   0

boot_message:     
    .string "Boot Loader Stage 2 loaded"             
booted_from_msg:
    .string "Booting from "
fd: .string "floppy disk"
hd: .string "hard drive"

continue_prompt:
    .string "Press Enter to continue"

sector_finsihed_prompt:
    .string "Fully read sector successfully!"

sector_to_read_prompt:
    .string "Enter sector number to read: (press enter to read sector 0)"