---
date: 2021-02-12 15:58:16
layout: post
title: "Setup a Raspberry Pi cluster with Talos"
subtitle: Talos, the OS that manages k8s for you.
description: Talos is an operating system made entirely for kubernetes. Everything else has been removed, letting you worry only about your cluster.
image: /assets/img/talos-header.png
optimized_image:
category: Kubernetes
tags: Kubernetes Talos Raspberry
author: bastienjeannelle
paginate: false
---

Being an unoriginal person, I have been quite tempted for a while to build a Kubernetes cluster on Raspberries Pi, which absolutely everyone does nowadays. Yet, I was not satisfied with building it on top of Raspbian or Ubuntu. What I really wanted was a kubernetes cluster, without having to worry about any underline, kind of a platform as a service. Talos seemed like the perfect solution.

> "Talos is a modern platform designed specifically to host Kubernetes clusters, running a flexible and powerful API-driven OS for kubernetes." <em>from [Talos' website](https://www.talos-systems.com)</em>

What does this means exactly ? Everything not related to kubernetes is <strong>removed</strong>. No shell, no SSH, fully immutable from boot to shutdown. Kubernetes-as-a-service, you only care about your cluster. I found this solution perfect for an internal Cloud!

<strong>However</strong>, by the time I am writing this post, Talos is still in Alpha (v0.9), and you might need to tweak around some configurations. They have community channels though, and are very quick to answer for support, so no need to worry.

This is what stimulated me to write posts about my journey with Talos: I believe it is the perfect tool to build a bare-metal PaaS even though it is still in Alpha. If this can help or encourage people to start using Talos, goal achieved!

# Requirements

* A pc / laptop running MacOS or linux, with [kubectl installed](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* at least 2 Raspberry Pi 4 model B. As many as you want and your wallet permits, but keep in mind that to reach High Availability and Reliability for etcd, 3 control plane nodes are needed. In this guide I will be using only 1 control plane node.
* Micro-sd card for each node, and a SD card adapter to connect to your PC / laptop. I went for 8GB micro-sd cards, as they will not store much. You can even go lower.
* 4 RJ45 cables, and a switch or router.
* Power adapter for each Raspberry. I went for a PoE switch and [PoE hats](https://www.raspberrypi.org/products/poe-hat/).
*  If you have access to your DHCP's client list, skip the next two items
  1. A screen.
  2. HDMI type D (micro HDMI) cable.


# Getting started

First thing first, remember how Talos has no SSH nor shell? That means we can only interact with the operating system through APIs. This is done through the command line <strong>talosctl</strong>. To install talosctl onto our local machine:
```bash
$ curl -Lo /usr/local/bin/talosctl https://github.com/talos-systems/talos/releases/latest/download/talosctl-$(uname -s | tr "[:upper:]" "[:lower:]")-amd64
$ chmod +x /usr/local/bin/talosctl
```

We can test if it has been correctly installed:

```bash
$ talosctl version
Client:
	Tag:         v0.8.0
	SHA:         cf5226a5
	Built:
	Go version:  go1.15.6
	OS/Arch:     darwin/amd64
```

We need to update every raspberry's EEPROM, so the following steps have to be repeted for eachof them. The path to the SD card can be found with <strong>fdisk</strong> on linux and <strong>diskutil</strong>. Let's assume the paths is /dev/mmcblk0:

<strong>Linux</strong>
```bash
$ curl -LO https://github.com/raspberrypi/rpi-eeprom/releases/download/v2020.09.03-138a1/rpi-boot-eeprom-recovery-2020-09-03-vl805-000138a1.zip
$ sudo mkfs.fat -I /dev/mmcblk0
$ sudo mount /dev/mmcblk0 /mnt
$ sudo bsdtar rpi-boot-eeprom-recovery-2020-09-03-vl805-000138a1.zip -C /mnt
```

<strong>MacOS</strong>
```bash 
$ curl -LO https://github.com/raspberrypi/rpi-eeprom/releases/download/v2020.09.03-138a1/rpi-boot-eeprom-recovery-2020-09-03-vl805-000138a1.zip
$ sudo diskutil eraseDisk FAT32 < name you want to give to the sd card> MBRFormat /dev/mmcblk0
$ sudo bsdtar xf rpi-boot-eeprom-recovery-2020-09-03-vl805-000138a1.zip -C /Volumes/< name you gave to the sd card> 
$ diskutil unmountDisk /dev/mmcblk0
```

Remove the SD card from your local machine and insert it into the Raspberry Pi. Power the Raspberry Pi on, and wait at least 10 seconds. If successful, the green LED light will blink rapidly (forever), otherwise an error pattern will be displayed. If an HDMI display is attached then the screen will display green for success or red if a failure occurs. Power off the Raspberry Pi and remove the SD card from it.

>Note: If the green light does not blink rapidly, you can find the error [here](https://www.talos.dev/docs/v0.8/single-board-computers/rpi_4/#bootstrapping-the-node), based on the light pattern.

EEPROM updated, we can write Talos' image on the sd card.

Download the image and decompress it:
```bash
$ curl -LO https://github.com/talos-systems/talos/releases/download/v0.8.0/metal-rpi_4-arm64.img.xz
xz -d metal-rpi_4-arm64.img.xz
```

Write the image to the sd card:
```bash
sudo dd if=metal-rpi_4-arm64.img of=/dev/mmcblk0 conv=fsync bs=4M
```
Repeat these steps for every raspberries you have. Once you are dine, it is now time to bootstrap our cluster!


# Bootstrap the cluster

## Create configuration files

Create a folder for Talos:

```bash 
$ mkdir talos-conf && cd talos-conf 
```

We need to generate configuration files for our nodes. Run ``` talosctl gen config talos-lab https://192.168.0.230:6443 ```. This generates YAML files to apply to the raspberries.

The cluster is here given the name talos-lab, but you can change it to your liking.
The IP address of the control plane should be a routable IP on your local network, and if possible outside of the DHCP range: this IP will be static and should not overlap with any other. 

4 files have been created:
* init.yaml : To be applied first to a raspberry: bootstrap the cluster and turns the node into controlplane node.
* join.yaml : Apply to a node to join the cluster as worker node.
* controlplane.yaml : Apply to a node to join the cluster as controlplane node.
* talosconfig: Config to talk with our cluster. This file is also created at ~/.talos/config. If not, copy talosconfig to ~/.talos/config.

## Control plane configuration

First file we need check is init.yaml. 
Change network settings according to your local network and IP address scheme:

```yaml 
# Provides machine specific network configuration options.
    network:
    # # `interfaces` is used to define the network interface configuration.
    interfaces:
        - interface: eth0 # The interface name.
          cidr: 192.168.0.230/24 # IP address configured earlier
          # A list of routes associated with the interface.
          routes:
            - network: 0.0.0.0/0 # The route's network.
              gateway: 192.168.0.1 # gateway of your network
              metric: 1024 # The optional metric for the route.
          mtu: 1500 # The interface's MTU.
          dhcp: false  # We want a static IP 
```
```yaml
install:
        disk: /dev/mmcblk0 # The disk used for installations.
```

These are the only changes you need to do to have a working configuration. You can change of course play around the settings, with Talos' [documentation](https://www.talos.dev/docs/v0.8/reference/configuration/#config)
Save this file and keep it for later. 

## Worker nodes configuration

Copy join.yaml and paste it as many worker nodes you have. In each file, modify these lines:

```yaml
network: {}
    # `interfaces` is used to define the network interface configuration.
    interfaces:
        - interface: eth0 # The interface name.
          cidr: 192.168.0.231/24 # Static IP of our node. MODIFY FOR EACH NODE.
          # A list of routes associated with the interface.
          routes:
            - network: 0.0.0.0/0 # The route's network.
              gateway: 192.168.0.1 # Your local network's gateway
              metric: 1024 # The optional metric for the route.
          mtu: 1500 # The interface's MTU.
          dhcp: false
```
```yaml
install:
        disk: /dev/mmcblk0 # The disk used for installations.
```

## Start the cluster

Turn the raspberry you want as control plane mode on, and plug the hdmi cable to a screen. Wait for it to boot, then wait for instructions asking you to apply configurations. Run: 
```bash $ tasloctl apply-config -insecure -n @IP_address_displayed -f init.yaml ```
Done! The cluster is being bootstrapped, and our control plane mode will be started short afterwards. Once the node is ready (no more new information is being displayed on the screen), retrive the kubectl config: ``` talosctl kubeconfig -n 192.168.0.230 ```

You can now turn the raspberries on one by one and follow the same procedure to apply their configs:
```bash $ talosctl apply-config -insecure -n @IP_address_displayed -f join.yaml ```

Congratulations, your Kubernetes cluster managed by Talos is up and running! Run ``` Kubectl get nodes ``` to make sure.


# What's next ?

You can join the Talos community on [slack](https://slack.dev.talos-systems.io) to get support and contribute to the project. You can follow my posts to setup components, starting with [storage management](https://blog.bastincloud.com/home/)