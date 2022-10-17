## Setup

## setup 的参数

1. 第一个参数, props

- props 是响应式的，并且会在传入新的 props 时同步更新。
- 解构 props 对象,会造成响应式丢失,可以使用 **toRef(),toRefs()**两个工具函数,来解决此问题

2. 第二个参数,context 上下文

- 其暴露了一些在开发中可能使用到的属性(**attrs,slots,emit,expose**)
- context 是非响应式的
- attrs 和 slots 是有状态的对象，会随着组件自身的更新而更新,但不是响应式的

```
export default {
  setup(props, context) {
    // 透传 Attributes（非响应式的对象，等价于 $attrs）
    console.log(context.attrs)

    // 插槽（非响应式的对象，等价于 $slots）
    console.log(context.slots)

    // 触发事件（函数，等价于 $emit）
    console.log(context.emit)

    // 暴露公共属性（函数）
    console.log(context.expose)
  }
}
```

## setup 的返回值, setup 可以返回一个对象,也可以返回一个函数

1. 返回的对象会暴露给模板和组件实例。其它的选项也可以通过组件实例来获取 setup() 暴露的属性

- 在模板中访问 setup 返回的 ref,会**自动浅层解包**(可以不使用.value),其本质是 proxyRefs 对 setup 的返回结果包了一层
- 通过 this 访问时也会自动浅层解包
- **在 setup() 中访问 this 会是 undefined**

```
<script>
import { ref } from 'vue'

export default {
  setup() {
    const count = ref(0)

    // 返回值会暴露给模板和其他的选项式 API 钩子
    return {
      count
    }
  },

  mounted() {
    console.log(this.count) // 0
  }
}
</script>

<template>
  <button @click="count++">{{ count }}</button>
</template>

```

2. 返回函数时,该函数会作为**渲染函数**(instance.render)

- 在渲染函数中可以使用在同一作用域下声明的响应式数据
- 如果想要暴露数据,可以使用 expose

## 单文件组件 <script setup>

TODO:----
