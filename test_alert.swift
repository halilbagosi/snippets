import AppKit

let alert = NSAlert()
alert.messageText = "Delete Collection?"
alert.informativeText = "What would you like to do with this collection and its contents?"
alert.alertStyle = .warning

let btn1 = alert.addButton(withTitle: "Delete Collection Only")
let btn2 = alert.addButton(withTitle: "Delete Collection & Contents")
let btn3 = alert.addButton(withTitle: "Cancel")

print("btn1:", btn1)
print("btn2:", btn2)
print("btn3:", btn3)
