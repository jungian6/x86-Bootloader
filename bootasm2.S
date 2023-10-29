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

# Displays the contents of the sector at 0xD000 in hexadecimal
display_sector:
    movw    $0xD000, %si
    movb    $0x80, %cl                   # 128 iterations (since we print 2 bytes at a time)

display_loop:
    movb    (%si), %al
    call    display_byte_hex             # Display byte in hex
    inc     %si
    movb    (%si), %al
    call    display_byte_hex             # Display byte in hex
    inc     %si

    dec     %cl
    jz      done_display
    jmp     display_loop

done_display:
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

# Program data

boot_device:
    .byte   0

boot_message:     
    .string "Boot Loader Stage 2 loaded"             
booted_from_msg:
    .string "Booting from "
fd: .string "floppy disk"
hd: .string "hard drive"