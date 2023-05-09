ifdef SNAPCRAFT_STAGE
STAGEDIR ?= "$(SNAPCRAFT_STAGE)"
else
STAGEDIR ?= "$(CURDIR)/stage"
endif
DESTDIR ?= "$(CURDIR)/install"
ARCH ?= $(shell dpkg --print-architecture)
GRUB_ARCH_amd64 := x64
GRUB_ARCH_arm64 := aa64
GRUB_ARCH = $(GRUB_ARCH_$(ARCH))
SHIM_SIGNED := $(STAGEDIR)/usr/lib/shim/shim$(GRUB_ARCH).efi.signed
SHIM_LATEST := $(SHIM_SIGNED).latest

# filtered list of modules included in the signed EFI grub image, excluding
# ones that we don't think are useful in snappy.
GRUB_MODULES_common = \
	all_video \
	boot \
	cat \
	chain \
	configfile \
	echo \
	ext2 \
	fat \
	font \
	gettext \
	gfxmenu \
	gfxterm \
	gfxterm_background \
	gzio \
	halt \
	jpeg \
	keystatus \
	loadenv \
	loopback \
	linux \
	memdisk \
	minicmd \
	normal \
	part_gpt \
	png \
	reboot \
	search \
	search_fs_uuid \
	search_fs_file \
	search_label \
	sleep \
	squash4 \
	test \
	true \
	btrfs \
	hfsplus \
	iso9660 \
	part_apple \
	part_msdos \
	password_pbkdf2 \
	zfs \
	zfscrypt \
	zfsinfo \
	lvm \
	mdraid09 \
	mdraid1x \
	raid5rec \
	raid6rec \
	video
GRUB_MODULES_amd64 = $(GRUB_MODULES_common) biosdisk
GRUB_MODULES_arm64 = $(GRUB_MODULES_common)
GRUB_MODULES = $(GRUB_MODULES_$(ARCH))

# which GRUB packages to stage
GRUB_PKGS_amd64 = \
	grub-pc-bin \
	grub-efi-amd64-signed \
	shim-signed
GRUB_PKGS_arm64 = \
	grub-efi-arm64-bin \
	grub-efi-arm64-signed \
	shim-signed
GRUB_PKGS = $(GRUB_PKGS_$(ARCH))

# needed in various pathnames; GRUB_FORMAT is the output format string
# as found in /usr/lib/grub and used as argument to grub-mk* commands
GRUB_FORMAT_amd64 = i386-pc
GRUB_FORMAT_arm64 = arm64-efi
GRUB_FORMAT = $(GRUB_FORMAT_$(ARCH))
# GRUB_FORMAT_SIGNED is similar, but for the signed binaries
GRUB_FORMAT_SIGNED_amd64 = x86_64-efi-signed
GRUB_FORMAT_SIGNED_arm64 = arm64-efi-signed
GRUB_FORMAT_SIGNED = $(GRUB_FORMAT_SIGNED_$(ARCH))

# Download the latest version of package $1 for architecture $(ARCH), unpacking
# it into $(STAGEDIR). For example, the following invocation will download the
# latest version of u-boot-rpi for armhf, and unpack it under STAGEDIR:
#
#  $(call stage_package,u-boot-rpi)
#
define stage_package
	mkdir -p $(STAGEDIR)/tmp
	( \
		cd $(STAGEDIR)/tmp && \
		apt-get download \
			-o APT::Architecture=$(ARCH) $$( \
				apt-cache \
					-o APT::Architecture=$(ARCH) \
					showpkg $(1) | \
					sed -n -e 's/^Package: *//p' | \
					sort -V | tail -1 \
			); \
	)
	dpkg-deb --extract $$(ls $(STAGEDIR)/tmp/$(1)*.deb | tail -1) $(STAGEDIR)
endef

all: boot install

boot:
	# Check if we're running under snapcraft. If not, we need to 'stage'
	# some packages by ourselves.
	$(info $(GRUB_PKGS))
ifndef SNAPCRAFT_PROJECT_NAME
	$(foreach pkg,$(GRUB_PKGS), \
	    $(call stage_package,$(pkg)); \
	)
endif
	if [ -e $(STAGEDIR)/usr/lib/grub/$(GRUB_FORMAT)/boot.img ]; then \
	    dd if=$(STAGEDIR)/usr/lib/grub/$(GRUB_FORMAT)/boot.img of=pc-boot.img bs=440 count=1; \
	    /bin/echo -n -e '\x90\x90' | dd of=pc-boot.img seek=102 bs=1 conv=notrunc; \
	fi
	grub-mkimage -d $(STAGEDIR)/usr/lib/grub/$(GRUB_FORMAT)/ -O $(GRUB_FORMAT) -o pc-core.img -p '(,gpt2)/EFI/ubuntu' $(GRUB_MODULES)
	# The first sector of the core image requires an absolute pointer to the
	# second sector of the image.  Since this is always hard-coded, it means our
	# BIOS boot partition must be defined with an absolute offset.  The
	# particular value here is 2049, or 0x01 0x08 0x00 0x00 in little-endian.
	/bin/echo -n -e '\x01\x08\x00\x00' | dd of=pc-core.img seek=500 bs=1 conv=notrunc

	if [ -f "$(SHIM_LATEST)" ]; then \
		cp $(SHIM_LATEST) shim.efi.signed; \
	else \
		cp $(SHIM_SIGNED) shim.efi.signed; \
	fi
	cp $(STAGEDIR)/usr/lib/grub/$(GRUB_FORMAT_SIGNED)/grub$(GRUB_ARCH).efi.signed grub$(GRUB_ARCH).efi

install:
	mkdir -p $(DESTDIR)
	if [ -f pc-boot.img ]; then \
	    install -m 644 pc-boot.img $(DESTDIR)/; \
	fi
	install -m 644 pc-core.img shim.efi.signed grub$(GRUB_ARCH).efi $(DESTDIR)/
	install -m 644 grub.conf grub.cfg $(DESTDIR)/
	# For classic builds we also need to prime the gadget.yaml
	mkdir -p $(DESTDIR)/meta
	cp gadget.yaml $(DESTDIR)/meta/
