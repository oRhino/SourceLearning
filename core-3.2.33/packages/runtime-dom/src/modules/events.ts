import { hyphenate, isArray } from '@vue/shared'
import {
  ComponentInternalInstance,
  callWithAsyncErrorHandling
} from '@vue/runtime-core'
import { ErrorCodes } from 'packages/runtime-core/src/errorHandling'

interface Invoker extends EventListener {
  value: EventValue
  attached: number
}

type EventValue = Function | Function[]

//在关于时间的存储和比较方面，我们使用的是高精时间，即 performance.now。
//但根据浏览器的不同，e.timeStamp 的值也会有所不同。它既可能是高精时间，也可能是非高精时间。
//因此，严格来讲，这里需要做兼容处理。不过在 Chrome 49、Firefox 54、Opera 36 以及之后的版本中，e.timeStamp 的值都是高精时间。

// Async edge case fix requires storing an event listener's attach timestamp.
const [_getNow, skipTimestampCheck] = /*#__PURE__*/ (() => {
  let _getNow = Date.now
  let skipTimestampCheck = false
  if (typeof window !== 'undefined') {
    // Determine what event timestamp the browser is using. Annoyingly, the
    // timestamp can either be hi-res (relative to page load) or low-res
    // (relative to UNIX epoch), so in order to compare time we have to use the
    // same timestamp type when saving the flush timestamp.
    if (Date.now() > document.createEvent('Event').timeStamp) {
      // if the low-res timestamp which is bigger than the event timestamp
      // (which is evaluated AFTER) it means the event is using a hi-res timestamp,
      // and we need to use the hi-res version for event listeners as well.
      _getNow = () => performance.now()
    }
    // #3485: Firefox <= 53 has incorrect Event.timeStamp implementation
    // and does not fire microtasks in between event propagation, so safe to exclude.
    const ffMatch = navigator.userAgent.match(/firefox\/(\d+)/i)
    skipTimestampCheck = !!(ffMatch && Number(ffMatch[1]) <= 53)
  }
  return [_getNow, skipTimestampCheck]
})()

// To avoid the overhead of repeatedly calling performance.now(), we cache
// and use the same timestamp for all event listeners attached in the same tick.
let cachedNow: number = 0
const p = /*#__PURE__*/ Promise.resolve()
const reset = () => {
  cachedNow = 0
}
const getNow = () => cachedNow || (p.then(reset), (cachedNow = _getNow()))

export function addEventListener(
  el: Element,
  event: string,
  handler: EventListener,
  options?: EventListenerOptions
) {
  el.addEventListener(event, handler, options)
}

export function removeEventListener(
  el: Element,
  event: string,
  handler: EventListener,
  options?: EventListenerOptions
) {
  el.removeEventListener(event, handler, options)
}
// 1. 先从el._vei 中读取对应的invokers，因为可能有多个事件,所以其是一个对象,通过事件名称获取对应的invoker,
// 如果invoker不存在，则将伪造的invoker作为事件处理函数，并将它缓存到el._vei属性中。
// 2. 如果缓存中没有缓存过的,并且nextValue有值,需要绑定方法,并且缓存起来
// 3. 以前绑定过需要删除掉,删除缓存
// 4. 如果前后都有,直接改变invoker中的value属性指向最新的事件即可
export function patchEvent(
  el: Element & { _vei?: Record<string, Invoker | undefined> },
  rawName: string,
  prevValue: EventValue | null,
  nextValue: EventValue | null,
  instance: ComponentInternalInstance | null = null
) {
  // vei = vue event invokers

  //定义 el._vei 为一个对象，存在事件名称到事件处理函数的映射
  const invokers = el._vei || (el._vei = {})
  // 根据事件名称获取invoker
  const existingInvoker = invokers[rawName]

  if (nextValue && existingInvoker) {
    // patch
    // 如果invoker存在，意味着更新，并且只需要更新 invoker.value 的值即可
    existingInvoker.value = nextValue
  } else {
    const [name, options] = parseName(rawName)
    if (nextValue) {
      // add
      // 不存在invoker就进行创建,将真正的事件处理函数赋值给 invoker.value,绑定invoker作为事件处理函数
      const invoker = (invokers[rawName] = createInvoker(nextValue, instance))
      addEventListener(el, name, invoker, options)
    } else if (existingInvoker) {
      // remove
      // 新的事件绑定函数不存在，且之前绑定的 invoker 存在，则移除绑定
      removeEventListener(el, name, existingInvoker, options)
      invokers[rawName] = undefined
    }
  }
}

const optionsModifierRE = /(?:Once|Passive|Capture)$/

function parseName(name: string): [string, EventListenerOptions | undefined] {
  let options: EventListenerOptions | undefined
  if (optionsModifierRE.test(name)) {
    options = {}
    let m
    while ((m = name.match(optionsModifierRE))) {
      name = name.slice(0, name.length - m[0].length)
      ;(options as any)[m[0].toLowerCase()] = true
    }
  }
  return [hyphenate(name.slice(2)), options]
}

// 绑定一个伪造的事件处理函数 invoker，然后把真正的事件处理函数设置为 invoker.value 属性的值。
// 这样当更新事件的时候，我们将不再需要调用 removeEventListener 函数来移除上一次绑定的事件，只需要更新 invoker.value 的值即可
// 优点:
// 1. 在更新事件时可以避免一次removeEventListener函数的调用，从而提升了性能。
// 2. 还能解决事件冒泡与事件更新之间相互影响的问题

function createInvoker(
  initialValue: EventValue,
  instance: ComponentInternalInstance | null
) {
  const invoker: Invoker = (e: Event) => {
    // async edge case #6566: inner click event triggers patch, event handler
    // attached to outer element during patch, and triggered again. This
    // happens because browsers fire microtask ticks between event propagation.
    // the solution is simple: we save the timestamp when a handler is attached,
    // and the handler would only fire if the event passed to it was fired
    // AFTER it was attached.
    //e.timeStamp 是事件触发的时间
    const timeStamp = e.timeStamp || _getNow()

    //屏蔽所有绑定时间晚于事件触发时间的事件处理函数的执行
    /**(比如父元素的事件是根据响应式数据进行绑定的,子元素绑定的事件函数中对响应式数据进行修改,
    触发更新,父元素的事件进行了绑定,由于事件冒泡,父元素的事件也进行了执行)
    Example: 
const { effect, ref } = VueReactivity
const bol = ref(false)
effect(() => {
  // 创建 vnode
  const vnode = {
    type: 'div',
    props: bol.value
      ? {
          onClick: () => {
            alert('父元素 clicked')
          }
        }
      : {},
    children: [
      {
        type: 'p',
        props: {
          onClick: () => {
            bol.value = true
          }
        },
        children: 'text'
      }
    ]
  }
  // 渲染 vnode
  renderer.render(vnode, document.querySelector('#app'))
})
    */

    // 只有事件发生的时间晚于事件处理函数绑定的时间，才执行事件处理函数
    if (skipTimestampCheck || timeStamp >= invoker.attached - 1) {
      //执行事件处理函数
      callWithAsyncErrorHandling(
        patchStopImmediatePropagation(e, invoker.value),
        instance,
        ErrorCodes.NATIVE_EVENT_HANDLER,
        [e]
      )
    }
  }
  invoker.value = initialValue
  //存储事件处理函数被绑定的时间
  invoker.attached = getNow()
  return invoker
}

function patchStopImmediatePropagation(
  e: Event,
  value: EventValue
): EventValue {
  // value是数组(一个元素同一个类型事件绑定多个处理函数)
  if (isArray(value)) {
    const originalStop = e.stopImmediatePropagation
    e.stopImmediatePropagation = () => {
      originalStop.call(e)
      ;(e as any)._stopped = true
    }
    // 遍历它并逐个调用事件处理函数
    return value.map(fn => (e: Event) => !(e as any)._stopped && fn && fn(e))
  } else {
    return value
  }
}
