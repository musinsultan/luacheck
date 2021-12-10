#!/usr/bin/env tarantool
net_box = require('net.box')
net_box.self:ping()