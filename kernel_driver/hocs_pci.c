/*
 * HOCS PCIe / AXI LINUX KERNEL DRIVER
 * ===================================
 * Module: hocs_pci
 * Author: Muhammed Yusuf Çobanoğlu
 * License: GPL
 * Description: 
 * Character device driver for HOCS FPGA Accelerator.
 * Maps FPGA AXI BARs to User Space and handles DMA Interrupts.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>
#include <linux/io.h>
#include <linux/interrupt.h>
#include <linux/of_address.h>
#include <linux/of_device.h>
#include <linux/platform_device.h>

#define DRIVER_NAME "hocs_accelerator"
#define HOCS_CLASS_NAME "hocs_fpga"

// Hardware Register Offsets (AXI Lite)
#define REG_CONTROL 0x00
#define REG_STATUS  0x04
#define REG_IRQ_ACK 0x08

// Global Driver State
struct hocs_dev_t {
    dev_t dev_num;
    struct cdev cdev;
    struct class *dev_class;
    struct device *dev_device;
    void __iomem *bar0_base; // Physical Memory Map
    int irq_number;
} hocs_dev;

// --- FILE OPERATIONS ---

static int hocs_open(struct inode *inode, struct file *file) {
    printk(KERN_INFO "HOCS: Device Opened by User Process\n");
    return 0;
}

static ssize_t hocs_read(struct file *file, char __user *buf, size_t len, loff_t *offset) {
    // Reads status from FPGA hardware register
    u32 status_reg = ioread32(hocs_dev.bar0_base + REG_STATUS);
    
    if (copy_to_user(buf, &status_reg, sizeof(status_reg))) {
        return -EFAULT;
    }
    printk(KERN_INFO "HOCS: Status Register Read: 0x%08X\n", status_reg);
    return sizeof(status_reg);
}

static ssize_t hocs_write(struct file *file, const char __user *buf, size_t len, loff_t *offset) {
    u32 cmd_reg;
    
    if (copy_from_user(&cmd_reg, buf, len)) {
        return -EFAULT;
    }
    
    // Write directly to FPGA Physical Memory (Dangerous & Powerful)
    iowrite32(cmd_reg, hocs_dev.bar0_base + REG_CONTROL);
    printk(KERN_INFO "HOCS: Command 0x%08X sent to Optical Core\n", cmd_reg);
    return len;
}

// --- INTERRUPT HANDLER (The Pulse of Hardware) ---
static irqreturn_t hocs_irq_handler(int irq, void *dev_id) {
    u32 irq_status = ioread32(hocs_dev.bar0_base + REG_IRQ_ACK);
    
    if (irq_status & 0x01) {
        printk(KERN_INFO "HOCS: Optical Calculation Completed (IRQ Triggered)\n");
        // Clear Interrupt
        iowrite32(0x01, hocs_dev.bar0_base + REG_IRQ_ACK);
        return IRQ_HANDLED;
    }
    return IRQ_NONE;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = hocs_open,
    .read = hocs_read,
    .write = hocs_write,
};

// --- MODULE INITIALIZATION ---

static int __init hocs_driver_init(void) {
    int ret;

    printk(KERN_INFO "HOCS: Initializing Kernel Module...\n");

    // 1. Allocate Major Number dynamically
    if (alloc_chrdev_region(&hocs_dev.dev_num, 0, 1, DRIVER_NAME) < 0) {
        return -1;
    }

    // 2. Create Device Class
    if ((hocs_dev.dev_class = class_create(THIS_MODULE, HOCS_CLASS_NAME)) == NULL) {
        unregister_chrdev_region(hocs_dev.dev_num, 1);
        return -1;
    }

    // 3. Create Device File (/dev/hocs_accelerator)
    if (device_create(hocs_dev.dev_class, NULL, hocs_dev.dev_num, NULL, DRIVER_NAME) == NULL) {
        class_destroy(hocs_dev.dev_class);
        unregister_chrdev_region(hocs_dev.dev_num, 1);
        return -1;
    }

    // 4. Initialize Character Device
    cdev_init(&hocs_dev.cdev, &fops);
    if (cdev_add(&hocs_dev.cdev, hocs_dev.dev_num, 1) == -1) {
        device_destroy(hocs_dev.dev_class, hocs_dev.dev_num);
        class_destroy(hocs_dev.dev_class);
        unregister_chrdev_region(hocs_dev.dev_num, 1);
        return -1;
    }

    // Note: real 'ioremap' and 'request_irq' would happen in the probe function
    // for a platform driver, but this structure demonstrates the logic.
    
    printk(KERN_INFO "HOCS: Kernel Module Loaded Successfully. /dev/%s created.\n", DRIVER_NAME);
    return 0;
}

static void __exit hocs_driver_exit(void) {
    cdev_del(&hocs_dev.cdev);
    device_destroy(hocs_dev.dev_class, hocs_dev.dev_num);
    class_destroy(hocs_dev.dev_class);
    unregister_chrdev_region(hocs_dev.dev_num, 1);
    printk(KERN_INFO "HOCS: Kernel Module Unloaded.\n");
}

module_init(hocs_driver_init);
module_exit(hocs_driver_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Muhammed Yusuf Cobanoglu");
MODULE_DESCRIPTION("Linux Driver for HOCS Optical Accelerator");
MODULE_VERSION("1.0");
