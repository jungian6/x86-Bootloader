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
    shr     $8, %ax            # Get the high byte of the offset to AH
    mov     %ah, %al          # Move AH to AL
    call    display_byte_hex   # Display the high byte

    mov     %cl, %al           # Get the low byte of the offset
    call    display_byte_hex   # Display the low byte

    call    print_space        # Print a space character
    ret


read_sector:
    movb    $0x10, %ah                  # Reset disk system
    int     $0x13

    # Set up the disk address packet to read sector 0
    movw    $0x1, disk_address_packet+2  # Number of sectors to read = 1
    movw    $0xD000, disk_address_packet+4 # Buffer address = 0xD000
    xorl    %eax, %eax
    movl    %eax, disk_address_packet+8   # LBA = 0


    movb    $0x42, %ah                    # Read disk sectors
    movb    (boot_device), %dl
    leaw    disk_address_packet, %si
    int     $0x13

    jc      read_failed
    ret

# Displays the contents of the sector at 0xD000 in hexadecimal format
display_sector:
    movw    $0xD000, %si        # Starting address of the sector
    movw    $0x0000, %cx        # Offset counter
    movw    %si, %di            # DI will be used to remember the start of the 16 bytes for ASCII display


display_outer_loop:
    call    display_offset     # Display the current offset
    movb    $0x10, %bh         # Number of bytes to display per line

display_inner_loop:
    movb    (%si), %al
    call    display_byte_hex   # Display the current byte in hex
    call    print_space        # Print a space character
    inc     %si                # Point to the next byte
    dec     %bh                # Decrement the byte counter for this line
    jz      new_line           # If we've displayed 16 bytes, move to a new line

    jmp     display_inner_loop

new_line:
    movw    %di, %si            # Point SI to the start of the 16 bytes we've just displayed
    call    display_ascii       # Display ASCII values
    call    cons_write_crlf     # Move to a new line
    add     $0x10, %di          # Move DI to next 16 bytes

    add     $0x10, %cx         # Increase the offset by 16
    cmp     $0x100, %cx        # Check if we've displayed all 256 bytes
    jz      done_display_sector
    jmp     display_outer_loop
done_display_sector:
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