log () {
        echo -e "\e[32m["$(date +'%T' )"]  \e[1m $1 \e[0m " #| tee -a "${LOG_FILE}"
}

logErr () {
          echo -e "\e[91m ["$(date +'%T' )"] ---> $1 \e[0m" #| tee -a "${LOG_FILE}"
}

# Create caching folder hierarchy to work with this architecture
setupWorkSpace () {
				if [ $EUID -ne 0 ]; then
					echo "This tool must be run as root."
					exit 1
				fi

        thisArch=$1
        mkdir -p ./cache/$thisArch
        mkdir -p ./work/$thisArch
        mkdir -p ./work/$thisArch/rootfs
        mkdir -p ./work/$thisArch/bootfs
        mkdir -p ./work/$thisArch/ISOmountPoint
        mkdir -p ./release/$thisArch

}

function getCachedVendors {
        #pishrink is needed to deflate the disk size at the end
        if [ ! -f ./cache/pishrink.sh ] ; then
                log "Downloading pishrink."
                cd ./cache
                wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
                chmod +x pishrink.sh
                cd ..
        else
                log "Using pishrink from cache."

        fi

        # Download or copy the official image from cache
        if [ ! -f ./cache/$thisArch/$imageName ]; then
                log "Downloading official image from internet."
                wget -P ./cache/$thisArch/  $imageSource
                7z e -o./cache/$thisArch/   ./cache/$thisArch/$zipName
                rm ./cache/$thisArch/$zipName

        else
                log "Using official image from cache."

        fi

}


function prepareBaseOs {
        if [ ! -f ./cache/$thisArch/$imageName-rdy2build ]; then
                log "Getting OS image ready to run in qemu and build. "
                cp -fv ./cache/$thisArch/$imageName ./cache/$thisArch/$imageName-rdy2build

                # Mounting image disk (but not the partitions yet)
                log "Mounting image."
                partQty=$(fdisk -l ./cache/$thisArch/$imageName-rdy2build | grep -o "^./cache/$thisArch/$imageName-rdy2build" | wc -l)

                echo $partQty partitions detected.
                log "Resizing root partition."

                # Add 5G to the image file
                truncate -s "5G" ./cache/$thisArch/$imageName-rdy2build

                # Inflate last partition to maximum available space.
                parted ./cache/$thisArch/$imageName-rdy2build --script "resizepart $partQty 100%" ;

                #mount the inage drive
                mountImage

                log "Resize the root file system to fill the new drive size."
                resize2fs /dev/mapper/loop${loopId}p$partQty

								log "Unmount OS image"
								umountImage



        else
                log "Using Ready to build image from cache"

        fi
}



function mountImage  {
        log "Mounting OS partitions."
        # mount partition table in /dev/loop
        loopId=$(kpartx -sav ./cache/$thisArch/$imageName-rdy2build |  cut -d" " -f3 | grep -o "[^a-z]" | head -n 1)

        if [ $partQty == 2 ] ; then
        #
                mount -v /dev/mapper/loop${loopId}p2 ./work/$thisArch/rootfs/
                mount -v /dev/mapper/loop${loopId}p1 ./work/$thisArch/rootfs/boot/

        elif [ $partQty == 1 ] ; then
                mount -v /dev/mapper/loop${loopId}p1 ./work/$thisArch/rootfs/

        else
                log "ERROR: unsuported amount of partitions."
                exit 1
        fi

}



function umountImage {
        umount ./work/$thisArch/bootfs
        umount ./work/$thisArch/rootfs
        kpartx -d ./cache/$thisArch/$imageName-rdy2build

}



function mountAndBind {
        # Mount the image and make the binds required to chroot.
        log "Mounting OS image."
        IFS=$'\n' #to split lines into array
        partitions=($(kpartx -sav ./work/$thisArch/$imageName |  cut -d" " -f3))
        partQty=${#partitions[@]}
        echo $partQty partitions detected.



        log "Mounting OS partitions."
        if [ $partQty == 2 ] ; then
                mount -v /dev/mapper/${partitions[1]} ./work/$thisArch/rootfs/
                mount -v /dev/mapper/${partitions[0]} ./work/$thisArch/rootfs/boot/

        elif [ $partQty == 1 ] ; then
                mount -v /dev/mapper/${partitions[0]} ./work/$thisArch/rootfs/

        else
                log "ERROR: unsuported amount of partitions."
                exit 1
        fi

        mount --bind /dev  ./work/$thisArch/rootfs/dev/
        mount --bind /dev/pts  ./work/$thisArch/rootfs/dev/pts
        mount --bind /sys  ./work/$thisArch/rootfs/sys/
        mount --bind /proc ./work/$thisArch/rootfs/proc/


        resize2fs /dev/mapper/${partitions[ $(($partQty - 1)) ]}

}



function addScripts {
        log "copying lysmarine on the image"
        cp -r ../lysmarine ./work/$thisArch/rootfs/
        chmod 0775 ./work/$thisArch/rootfs/lysmarine/*.sh
        chmod 0775 ./work/$thisArch/rootfs/lysmarine/*/*.sh
}



function unmountOs {
        # The file transfer is done now, unmouting
        mv ./work/$thisArch/rootfs/etc/resolv.conf.lysmarinebak ./work/$thisArch/rootfs/etc/resolv.conf

        # Unmount the image
        log "Unmounting partitions"
        umount ./work/$thisArch/rootfs/dev/pts
        umount ./work/$thisArch/rootfs/dev/
        umount ./work/$thisArch/rootfs/sys/
        umount ./work/$thisArch/rootfs/proc/
        umount /dev/mapper/${partitions[0]}
        umount /dev/mapper/${partitions[1]}
        kpartx -d ./work/$thisArch/$imageName
}
