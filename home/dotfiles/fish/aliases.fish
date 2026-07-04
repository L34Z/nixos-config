alias aconf 'nano ~/.config/fish/aliases.fish'
alias ff 'fzf --preview \'bat {}\''
alias la 'eza --long --header --icons --git --no-user'
alias ls 'eza --icons'
alias rmd 'rm  --recursive --force --verbose'
alias refish 'exec fish'
alias pwrd 'systemctl poweroff'
alias pwrc 'systemctl reboot'

alias cp 'cp -i'
alias mv 'mv -i'
alias ps 'ps auxf'
alias ping 'ping -c 10'
alias cls clear


alias home 'cd ~'
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'
alias ..... 'cd ../../../..'


alias udc 'udisksctl'



#### MISC ####
alias weather 'curl wttr.in'


#### WINDOWS 11 VM (RTX 3080 passthrough + Looking Glass) ####
# win11            start the VM if it isn't up, then open the Looking Glass window
# win11 stop       graceful ACPI shutdown
# win11 kill       force off (virsh destroy) — use if the guest hangs
# win11 status     print the domain state
# Domain lives on qemu:///system; LG reads ~/.config/looking-glass/client.ini.
function win11
    set -l uri qemu:///system
    switch "$argv[1]"
        case '' start view
            if test "$(virsh -c $uri domstate win11 2>/dev/null)" != running
                echo "Starting win11…"
                virsh -c $uri start win11; or return 1
            end
            # LG mmaps /dev/shm/looking-glass, which qemu creates during device
            # setup. Wait for it so LG doesn't race in and die with "Invalid
            # path to the ivshmem file"; give up after ~10s so a failed start
            # doesn't hang the shell.
            for i in (seq 20)
                test -e /dev/shm/looking-glass; and break
                sleep 0.5
            end
            if not test -e /dev/shm/looking-glass
                echo "win11: /dev/shm/looking-glass never appeared — did the VM start? (virsh -c $uri domstate win11)" >&2
                return 1
            end
            looking-glass-client &; disown
        case stop shutdown
            virsh -c $uri shutdown win11
        case kill destroy force
            virsh -c $uri destroy win11
        case status state
            virsh -c $uri domstate win11
        case '*'
            echo "usage: win11 [start|stop|kill|status]"
    end
end



#### FUNCTIONS ####

# mount
function mnt
	udisksctl mount -b /dev/$argv
end
# unmount
function umnt
	udisksctl unmount -b /dev/$argv
end

# mkdir and move 
function md
    mkdir $argv && cd $argv
end


# send filetype to destination
function to
    if test (count $argv) -ne 2
        echo "Usage: to <destination> <filetype>"
        return 1
    end

    set dest $argv[1]
    set type $argv[2]

    # Check if destination exists and is a directory
    if not test -d $dest
        echo "Error: Destination '$dest' is not a directory"
        return 1
    end

    # Check if any files of the specified type exist
    if not count *.{$type} >/dev/null
        echo "No files with extension .$type found"
        return 1
    end

    # Move all files of specified type to destination
    mv *.{$type} $dest/
    echo "Moved all .$type files to $dest"
end

# bat command output
alias alist 'alias | bat'
function o
	$argv | bat
end


# rename folder to folder.bak
function bak
    mv $argv{,.bak}
end


# kill all pids matching name
function ka
    for pid in (pidof $argv)
        kill $pid
    end
end


# shred then delete file
function wipe
    shred --verbose $argv && rm $argv
    echo "File '$argv' destroyed!"
end
