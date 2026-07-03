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
