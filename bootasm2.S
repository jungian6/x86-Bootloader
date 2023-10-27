# When the PC starts, the processor is essentially emulating an 8086 processor, i.e. 
# a 16-bit processor.  So our initial boot loader code is 16-bit code that will 
# eventually switch the processor into 32-bit mode.

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

read_sector_number:
    xor     %cx, %cx            # CX register will hold the sector number
    xor     %dx, %dx            # DX register will be used to store individual digits

    # Get the current cursor position
    mov     $0x03, %ah          # AH = 3, get cursor position function
    mov     $0x00, %bh          # BH = 0, page number
    int     $0x10               # Call video interrupt
    # DH = row, DL = column, save them for later use
    mov     %dh, %ch            # CH = original row
    mov     %dl, %cl            # CL = original column

read_character:
    mov     $0x0, %ah
    int     $0x16               # BIOS read character
    cmp     $0x0D, %al          # Check if 'Enter' was pressed
    je      done_reading
    cmp     $0x30, %al          # Check if character is below '0'
    jb      read_character
    cmp     $0x39, %al          # Check if character is above '9'
    ja      read_character

    # Echo the character back to the screen
    movb    $0x0e, %ah          # Teletype output function
    int     $0x10               # BIOS video interrupt, AL already contains the character

    # Convert from ASCII to integer and update CX
    sub     $0x30, %al          # Convert from ASCII
    imul    $10, %cx, %cx       # Multiply current number by 10
    add     %al, %cl            # Add new digit to CX (lower 8 bits)

    jmp     read_character      # Repeat the process



done_reading:
    # Set up the parameters for the int $0x13 call
    mov     $0x02, %ah          # AH = 2, read sector function
    mov     %cx, %ax            # AL = number of sectors to read (1 in this case)
    xor     %bx, %bx            # BX = buffer address (0x0000 for offset)
    mov     $0x8000, %ax
    mov     %ax, %es
    movb    (boot_device), %dl  # DL = drive number

    # Set CH, CL, and DH for the int 0x13 call
    xor     %dh, %dh            # DH = head number (0 for simplicity)
    mov     %cx, %ax            # Copy sector number to AX
    and     $0xFF, %al          # AL = sector number (lower 8 bits)
    mov     %al, %cl            # Move sector number to CL
    shr     $8, %ah            # Shift right 8 bits to get upper 8 bits of sector number
    and     $0x03, %ah          # Mask all but the lower 2 bits
    mov     %ah, %ch            # Move to CH (upper 2 bits of sector number)

    int     $0x13               # Call disk interrupt


    mov     $0x8000, %si        # SI points to the start of the buffer
    mov     $512, %cx           # 512 bytes in a sector
    xor     %bx, %bx            # BX will hold the offset

display_loop:
    # Display the offset at the start of each line
    push    %cx                 # Save CX
    mov     %cx, %bx            # Move the offset to CX for display
    call    display_word_hex    # Display BX (offset) in hexadecimal
    movb    $0x20, %al          # Space character
    mov     $0x0E, %ah          # Teletype output function
    int     $0x10               # BIOS video interrupt
    pop     %cx                 # Restore CX

    # Display 16 bytes per line
    mov     $16, %bp            # Counter for 16 bytes per line
line_loop:
    lodsb                       # Load byte at SI into AL and increment SI
    call    display_byte_hex    # Display AL in hexadecimal
    dec     %bp                 # Decrement BP
    jz      newline             # If BP reaches 0, print a newline and continue with the next line
    movb    $0x20, %al          # Space character
    mov     $0x0E, %ah          # Teletype output function
    int     $0x10               # BIOS video interrupt
    inc     %bx                 # Increment the offset
    loop    line_loop           # Repeat for all bytes in the line

newline:
    # Print a newline
    call    cons_write_crlf
    inc     %di                 # Increment line counter
    cmp     $16, %di            # Check if 16 lines have been displayed
    jne     display_loop        # If not, continue with the next line

    # Pause after 16 lines
    movw    $pause_message, %si
    call    cons_write          # Display "Press any key to continue..."
    call    wait_for_key        # Wait for a key press
    call    clear_line          # Clear the "Press any key to continue..." message
    xor     %di, %di            # Reset line counter
    jmp     display_loop        # Continue with the next set of lines

wait_for_key:
    xor     %ah, %ah
    int     $0x16               # BIOS read character
    ret

clear_line:
    # Clear the current line (assuming 80 columns)
    mov     $0x20, %al          # Space character
    mov     $80, %cx            # Number of columns
clear_loop:
    mov     $0x0E, %ah          # Teletype output function
    int     $0x10               # BIOS video interrupt
    loop    clear_loop
    ret

pause_message:
    .string "Press any key to continue..."

display_word_hex:
    push    %ax                 # Save AX
    shr     $8, %al             # Shift right 8 bits to get the high byte
    call    display_byte_hex    # Display the high byte in hexadecimal
    pop     %ax                 # Restore AX
    and     $0x00FF, %ax        # Mask the high byte to get the low byte
    call    display_byte_hex    # Display the low byte in hexadecimal
    ret


read_error:
    # Display error code
    mov     %ah, %al            # Move the error code to AL
    call    display_byte_hex    # Display the error code in hexadecimal

    # Check specific error codes and display appropriate messages
    cmp     $0x01, %ah          # Invalid function or parameter
    je      display_invalid_function_msg
    cmp     $0x02, %ah          # Address mark not found
    je      display_address_mark_msg
    cmp     $0x03, %ah          # Disk write-protected
    je      display_write_protected_msg
    cmp     $0x04, %ah          # Sector not found/read error
    je      display_sector_not_found_msg
    cmp     $0x0A, %ah          # Bad sector flag detected
    je      display_bad_sector_msg
    # ... Add more error codes as needed

    # Default error message
    movw    $read_error_msg, %si
    call    cons_writeline
    ret

display_invalid_function_msg:
    movw    $invalid_function_msg, %si
    jmp     cons_writeline
display_address_mark_msg:
    movw    $address_mark_msg, %si
    jmp     cons_writeline
display_write_protected_msg:
    movw    $write_protected_msg, %si
    jmp     cons_writeline
display_sector_not_found_msg:
    movw    $sector_not_found_msg, %si
    jmp     cons_writeline
display_bad_sector_msg:
    movw    $bad_sector_msg, %si
    jmp     cons_writeline


display_byte_hex:
    # Display the byte in AL in hexadecimal format
    push    %ax                 # Save AX
    shr     $4, %al             # Shift right 4 bits to get the high nibble
    call    display_nibble_hex  # Display the high nibble
    pop     %ax                 # Restore AX
    and     $0x0F, %al          # Mask the high nibble to get the low nibble
    call    display_nibble_hex  # Display the low nibble
    ret

display_nibble_hex:
    # Display the 4-bit value in AL in hexadecimal format
    cmp     $0xA, %al           # Check if AL is 10 or greater
    jl      display_digit       # If less, it's a digit
    add     $7, %al             # Convert 10-15 to 'A'-'F'
display_digit:
    add     $0x30, %al          # Convert 0-9 to '0'-'9'
    # Display AL
    mov     $0x0E, %ah          # Teletype output function
    int     $0x10               # BIOS video interrupt
    ret

call    read_sector_number


real_start:
    movb    %dl, (boot_device) # Boot device number is passed in DL from BIOS. Save it hear since DL might get trashed

    movw    $boot_message, %si  # Display our boot message
    call    cons_writeline

    movw    $booted_from_msg, %si
    call    cons_write

    movb    (boot_device), %dl
    cmp     $0x80, %dl
    jge     harddrive

    movw    $fd, %si
    jmp     finish

harddrive:
    movw    $hd, %si

finish:
    call    cons_writeline

# Print the prompt
movw    $prompt_message, %si
call    cons_write  # not cons_writeline, because we don't want a newline this time

# Get the current cursor position
mov     $0x03, %ah          # AH = 3, get cursor position function
mov     $0x00, %bh          # BH = 0, page number
int     $0x10               # Call video interrupt
# Save current position
mov     %dh, %ch            # CH = original row
mov     %dl, %cl            # CL = original column

# Now, CL contains the column number where the cursor is after printing the prompt.
# You don't need to change it because you want to start input right after the prompt.
# Proceed to read characters and echo them back as you were doing.
 call    read_sector_number 



endless_loop:                   # Loop forever more
    jmp     endless_loop    

# Program data

invalid_function_msg:
    .string "Invalid function or parameter."
address_mark_msg:
    .string "Address mark not found."
write_protected_msg:
    .string "Disk is write-protected."
sector_not_found_msg:
    .string "Sector not found or read error."
bad_sector_msg:
    .string "Bad sector detected."

boot_device:
    .byte   0

read_error_msg:
    .string "Error reading sector. Please try again."
boot_message:     
    .string "Boot Loader Stage 2 loaded"             
booted_from_msg:
    .string "Booting from "
fd: .string "floppy disk"
hd: .string "hard drive"
prompt_message:
    .string "Enter the sector number to read: "