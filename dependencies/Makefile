all: mpvcontextmenu/patch.applied fformation munkres
	make -C munkres
	make -C fformation

mpvcontextmenu/patch.applied:
	cd mpvcontextmenu && git apply ../mpvcontextmenu.patch

clean:
	make -C munkres clean
	make -C fformation clean
	cd mpvcontextmenu && git reset --hard && rm -f patch.applied
