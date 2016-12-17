# VDom

VDom is a virtual DOM library implemented on top of HxBit

It can be implemented by a Javascript Server by extending `vdom.Server` which we can connect to using a Client extending `vdom.Client`

The client can then manipulate the distant server DOM using `vdom.JQuery` as he would do directly if he was written in JS.

ATM only a partial implementation of JQuery is available.
