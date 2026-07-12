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
# win11 backup     force the VM off, then snapshot the disk into backups/
# win11 restore F  force the VM off, then overwrite the disk with snapshot F
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
        case backup
            set -l vmdir ~/vms/win11
            # Hard power-off: ACPI shutdown stalls in the Windows guest, so
            # just yank it. The backup is crash-consistent (NTFS journals).
            if test "$(virsh -c $uri domstate win11 2>/dev/null)" = running
                echo "Killing win11…"
                virsh -c $uri destroy win11; or return 1
            end
            if test "$(virsh -c $uri domstate win11 2>/dev/null)" != "shut off"
                echo "win11: guest isn't off — refusing to snapshot a live disk." >&2
                return 1
            end
            mkdir -p $vmdir/backups; or return 1
            set -l dest $vmdir/backups/win11-(date +%F_%H-%M).img
            echo "Snapshotting to $dest…"
            # reflink: instant on btrfs, costs ~0 bytes until the live image
            # diverges. `command cp` dodges the cp -i alias above.
            command cp --reflink=always $vmdir/win11.img $dest; or return 1
            echo "Done. Backups:"
            command ls -lh $vmdir/backups/
        case restore
            set -l vmdir ~/vms/win11
            set -l src $argv[2]
            if test -z "$src"
                echo "usage: win11 restore <snapshot.img>" >&2
                return 1
            end
            if not test -f "$src"
                echo "win11: no such file: $src" >&2
                return 1
            end
            if test "$(virsh -c $uri domstate win11 2>/dev/null)" = running
                echo "Killing win11…"
                virsh -c $uri destroy win11; or return 1
            end
            if test "$(virsh -c $uri domstate win11 2>/dev/null)" != "shut off"
                echo "win11: guest isn't off — refusing to overwrite a live disk." >&2
                return 1
            end
            read -l -P "Overwrite $vmdir/win11.img with $src? [y/N] " ok
            if test "$ok" != y -a "$ok" != Y
                echo "Aborted."
                return 1
            end
            echo "Restoring from $src…"
            command cp --reflink=always "$src" $vmdir/win11.img; or return 1
            echo "Done."
        case '*'
            echo "usage: win11 [start|stop|kill|status|backup|restore <file>]"
    end
end



#### COMFYUI VM (RTX 3080 passthrough, plain QEMU — no libvirt) ####
# comfy            boot the VM if it isn't up, then attach the root console
#                  (detach with Ctrl-] — the VM keeps running; UI: http://localhost:8188)
# comfy stop       graceful shutdown (ACPI power button via the qemu monitor)
# comfy kill       force off (SIGTERM to qemu) — use if the guest hangs
# comfy status     running / shut off
# comfy serve [P]  forward host 127.0.0.1:P (default 8000) -> guest P, for
#                  pulling files out: `python3 -m http.server P -d …` in the
#                  guest. Deliberately per-run (gone at shutdown): the share
#                  path only exists when you've just created it.
# Runner is `comfyui-vm` (flake.nix); its env knobs (COMFYUI_VM_NO_GPU=1 etc.)
# pass straight through: `COMFYUI_VM_NO_GPU=1 comfy`. Console + monitor live on
# sockets in $XDG_RUNTIME_DIR so they vanish with the session.
function comfy
    set -l rt (test -n "$XDG_RUNTIME_DIR"; and echo $XDG_RUNTIME_DIR; or echo /tmp)
    set -l con $rt/comfyui-vm.console
    set -l mon $rt/comfyui-vm.monitor
    set -l log $rt/comfyui-vm.log
    # -name comfyui is unique to this VM (win11's qemu uses -name guest=win11)
    set -l pat 'qemu-system-x86_64 .*-name comfyui'
    switch "$argv[1]"
        case '' start console
            if not pgrep -f $pat >/dev/null
                echo "Starting comfyui VM… (log: $log)"
                command rm -f $con $mon
                # Headless: the web UI is the real interface, and a serial
                # socket console can re-attach at will — closing a qemu GTK
                # window would kill the VM instead. QEMU_KERNEL_PARAMS lands
                # last on the cmdline, making ttyS0 the primary console so
                # boot messages show up here too.
                env QEMU_KERNEL_PARAMS="console=ttyS0,115200n8" \
                    comfyui-vm -display none \
                    -serial unix:$con,server=on,wait=off \
                    -monitor unix:$mon,server=on,wait=off \
                    </dev/null >$log 2>&1 &
                set -l pid $last_pid
                disown
                # qemu creates the sockets during startup, but VFIO has to pin
                # 20 GiB of guest RAM first — wait, and bail early with the log
                # if the runner died (win11 holding the GPU, memlock, …).
                for i in (seq 40)
                    test -S $con; and break
                    if not test -e /proc/$pid
                        echo "comfy: VM died on startup:" >&2
                        tail -n 5 $log >&2
                        return 1
                    end
                    sleep 0.5
                end
            end
            if not test -S $con
                echo "comfy: no console socket at $con — VM started outside `comfy`? (check $log)" >&2
                return 1
            end
            # the serial chardev only takes one client; a second attach would
            # fight the first for bytes
            if pgrep -f "socat.*$con" >/dev/null
                echo "comfy: console already attached in another terminal."
                return 0
            end
            echo "Attaching console — detach with Ctrl-] (VM keeps running)."
            socat -,raw,echo=0,escape=0x1d unix-connect:$con
        case serve
            if not test -S $mon
                echo "comfy: not running (no monitor socket)." >&2
                return 1
            end
            set -l port (test -n "$argv[2]"; and echo $argv[2]; or echo 8000)
            echo "hostfwd_add tcp:127.0.0.1:$port-:$port" | socat - unix-connect:$mon >/dev/null
            # the monitor echoes line noise, not a status — verify the bind
            if not ss -tln | string match -q "*127.0.0.1:$port *"
                echo "comfy: host isn't listening on $port — port taken? (qemu prints the reason on its stdout: see comfy log at startup)" >&2
                return 1
            end
            echo "Forwarding host 127.0.0.1:$port -> guest $port (until VM shutdown)."
            echo "In the guest console:  python3 -m http.server $port -d /data/ComfyUI/output"
            test "$port" = 8000
            or echo "NB: the guest firewall only opens 8000 (+8188) — for port $port also run: iptables -I nixos-fw -p tcp --dport $port -j ACCEPT"
        case stop shutdown
            if not test -S $mon
                echo "comfy: not running (no monitor socket)." >&2
                return 1
            end
            echo system_powerdown | socat - unix-connect:$mon >/dev/null
        case kill destroy force
            pkill -f $pat
        case status state
            if pgrep -f $pat >/dev/null
                echo running
            else
                echo "shut off"
            end
        case '*'
            echo "usage: comfy [start|serve [port]|stop|kill|status]"
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
