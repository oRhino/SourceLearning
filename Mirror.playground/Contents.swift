//: Playground - noun: a place where people can play

import UIKit

class Person:CustomStringConvertible{
    var name:String
    var age:UInt
    var address:String
    init(name:String,age:UInt,address:String) {
        self.name = name
        self.age = age
        self.address = address
    }
    var description: String{
        return "name: " + self.name + "age: \(self.age) " + "address: " + self.address
    }
    
}

let xiaoli = Person(name: "xiaoli", age: 24, address: "BeiJing")

dump(xiaoli)


let reflect = Mirror(reflecting: xiaoli)

//所有成员属性通过 Mirror 初始化得到的结果中包含的元素的描述都被集合在 children 属性下
for property in reflect.children{
    print("\(property.label!) : \(property.value)")
}

//类型 class struct....
print(reflect.displayStyle)

//Person.Type
reflect.subjectType

reflect.superclassMirror






