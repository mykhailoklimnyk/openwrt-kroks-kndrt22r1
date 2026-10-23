define Device/kroks_kndrt22r1
  SOC := mt7620a
  IMAGE_SIZE := 15040k
  DEVICE_VENDOR := Kroks
  DEVICE_MODEL := Rt-Brd eX
  DEVICE_ALT0_VENDOR := Kroks
  DEVICE_ALT0_MODEL := KNdRt22R1
  DEVICE_PACKAGES := kmod-usb2 kmod-usb-ohci kmod-usb-net-qmi-wwan kmod-usb-serial-option uqmi
  SUPPORTED_DEVICES += kndrt22r1
endef
TARGET_DEVICES += kroks_kndrt22r1
