import {
  isRef,
  isShallow,
  Ref,
  ComputedRef,
  ReactiveEffect,
  isReactive,
  ReactiveFlags,
  EffectScheduler,
  DebuggerOptions
} from '@vue/reactivity'
import { SchedulerJob, queuePreFlushCb } from './scheduler'
import {
  EMPTY_OBJ,
  isObject,
  isArray,
  isFunction,
  isString,
  hasChanged,
  NOOP,
  remove,
  isMap,
  isSet,
  isPlainObject
} from '@vue/shared'
import {
  currentInstance,
  ComponentInternalInstance,
  isInSSRComponentSetup,
  setCurrentInstance,
  unsetCurrentInstance
} from './component'
import {
  ErrorCodes,
  callWithErrorHandling,
  callWithAsyncErrorHandling
} from './errorHandling'
import { queuePostRenderEffect } from './renderer'
import { warn } from './warning'
import { DeprecationTypes } from './compat/compatConfig'
import { checkCompatEnabled, isCompatEnabled } from './compat/compatConfig'
import { ObjectWatchOptionItem } from './componentOptions'

export type WatchEffect = (onCleanup: OnCleanup) => void

export type WatchSource<T = any> = Ref<T> | ComputedRef<T> | (() => T)

export type WatchCallback<V = any, OV = any> = (
  value: V,
  oldValue: OV,
  onCleanup: OnCleanup
) => any

type MapSources<T, Immediate> = {
  [K in keyof T]: T[K] extends WatchSource<infer V>
    ? Immediate extends true
      ? V | undefined
      : V
    : T[K] extends object
    ? Immediate extends true
      ? T[K] | undefined
      : T[K]
    : never
}

type OnCleanup = (cleanupFn: () => void) => void

export interface WatchOptionsBase extends DebuggerOptions {
  flush?: 'pre' | 'post' | 'sync'
}

export interface WatchOptions<Immediate = boolean> extends WatchOptionsBase {
  immediate?: Immediate
  deep?: boolean
}

export type WatchStopHandle = () => void

// watch与watchEffect的区别
// watch只会追踪在source中明确的数据源，不会追踪回调函数中访问到的东西。
// 而且只在数据源发生变化后触发回调。
// watch会避免在发生副作用时追踪依赖（当发生副作用时，会执行调度器，
// 在调度器中会将job推入不同的任务队列，达到控制回调函数的触发时机的目的）
// 因此，我们能更加精确地控制回调函数的触发时机。

// watchEffect，会在副作用发生期间追踪依赖。它会在同步执行过程中，自动追踪所有能访问到的响应式property

// Simple effect.
export function watchEffect(
  effect: WatchEffect,
  options?: WatchOptionsBase
): WatchStopHandle {
  return doWatch(effect, null, options)
}

export function watchPostEffect(
  effect: WatchEffect,
  options?: DebuggerOptions
) {
  return doWatch(
    effect,
    null,
    (__DEV__
      ? { ...options, flush: 'post' }
      : { flush: 'post' }) as WatchOptionsBase
  )
}

export function watchSyncEffect(
  effect: WatchEffect,
  options?: DebuggerOptions
) {
  return doWatch(
    effect,
    null,
    (__DEV__
      ? { ...options, flush: 'sync' }
      : { flush: 'sync' }) as WatchOptionsBase
  )
}

// initial value for watchers to trigger on undefined initial values
const INITIAL_WATCHER_VALUE = {}

type MultiWatchSources = (WatchSource<unknown> | object)[]

// overload: array of multiple sources + cb
export function watch<
  T extends MultiWatchSources,
  Immediate extends Readonly<boolean> = false
>(
  sources: [...T],
  cb: WatchCallback<MapSources<T, false>, MapSources<T, Immediate>>,
  options?: WatchOptions<Immediate>
): WatchStopHandle

// overload: multiple sources w/ `as const`
// watch([foo, bar] as const, () => {})
// somehow [...T] breaks when the type is readonly
export function watch<
  T extends Readonly<MultiWatchSources>,
  Immediate extends Readonly<boolean> = false
>(
  source: T,
  cb: WatchCallback<MapSources<T, false>, MapSources<T, Immediate>>,
  options?: WatchOptions<Immediate>
): WatchStopHandle

// overload: single source + cb
export function watch<T, Immediate extends Readonly<boolean> = false>(
  source: WatchSource<T>,
  cb: WatchCallback<T, Immediate extends true ? T | undefined : T>,
  options?: WatchOptions<Immediate>
): WatchStopHandle

// overload: watching reactive object w/ cb
export function watch<
  T extends object,
  Immediate extends Readonly<boolean> = false
>(
  source: T,
  cb: WatchCallback<T, Immediate extends true ? T | undefined : T>,
  options?: WatchOptions<Immediate>
): WatchStopHandle

// implementation 实现
/**
 *
 * @param source  source监听的源
 * @param cb  cb回调函数
 * @param options options监听配置
 * @returns  返回一个停止监听函数。
 */
export function watch<T = any, Immediate extends Readonly<boolean> = false>(
  source: T | WatchSource<T>,
  cb: any,
  options?: WatchOptions<Immediate>
): WatchStopHandle {
  if (__DEV__ && !isFunction(cb)) {
    warn(
      `\`watch(fn, options?)\` signature has been moved to a separate API. ` +
        `Use \`watchEffect(fn, options?)\` instead. \`watch\` now only ` +
        `supports \`watch(source, cb, options?) signature.`
    )
  }
  return doWatch(source as any, cb, options)
}

/**
 * dowatch中会首先生成一个getter函数。
 * 如果是watchAPI，那么这个getter函数中会根据传入参数，
 * 访问监听数据源中的属性（可能会递归访问对象中的属性，取决于deep）
 * 并返回与数据源数据类型一致的数据（如果数据源是ref类型，getter函数返回ref.value；
 * 如果数据源类型是reactive，getter函数返回值也是reactive；
 * 如果数据源是数组，那么getter函数返回值也应该是数组；
 * 如果数据源是函数类型，那么getter函数返回值是数据源的返回值）。
 * 如果是watchEffect等API，那么getter函数中会执行source函数。
 * 然后定义一个job函数。如果是watch，job函数中会执行effect.run获取新的值，并比较新旧值，是否执行cb；
 * 如果是watchEffect等API，job中执行effect.run。那么如何只监听到state.obj.num的变换呢？
 * 当声明完job，会紧跟着定义一个调度器，这个调度器的作用是根据flush将job放到不同的任务队列中。
 * 然后根据getter与调度器scheduler初始化一个ReactiveEffect`实例。
 * 接着进行初始化：如果是watch，如果是立即执行，则马上执行job，否则执行effect.run更新oldValue；
 * 如果flush是post，会将effect.run函数放到延迟队列中延迟执行；其他情况执行effect.run。
 * 最后返回一个停止watch的函数。
 */

/**
 * Watch API 核心 watch,watchEffect、watchPostEffect、watchSyncEffect都将调用该函数
 * @param source 监听的数据源
 * @param cb 回调函数
 * @param param2 配置选项 (immediate, deep, flush, onTrack, onTrigger)
 * @returns
 */
function doWatch(
  source: WatchSource | WatchSource[] | WatchEffect | object,
  cb: WatchCallback | null,
  { immediate, deep, flush, onTrack, onTrigger }: WatchOptions = EMPTY_OBJ
): WatchStopHandle {
  //对immediate、deep做校验，如果cb为null，immediate、deep不为undefined进行提示
  if (__DEV__ && !cb) {
    if (immediate !== undefined) {
      warn(
        `watch() "immediate" option is only respected when using the ` +
          `watch(source, callback, options?) signature.`
      )
    }
    if (deep !== undefined) {
      warn(
        `watch() "deep" option is only respected when using the ` +
          `watch(source, callback, options?) signature.`
      )
    }
  }

  const warnInvalidSource = (s: unknown) => {
    warn(
      `Invalid watch source: `,
      s,
      `A watch source can only be a getter/effect function, a ref, ` +
        `a reactive object, or an array of these types.`
    )
  }

  // 当前组件实例
  const instance = currentInstance
  let getter: () => any // 副作用函数，在初始化effect时使用
  let forceTrigger = false // 强制触发监听
  let isMultiSource = false // 是否为多数据源。

  if (isRef(source)) {
    // 如果source是ref类型，getter是个返回source.value的函数，forceTrigger取决于source是否是浅层响应式。
    getter = () => source.value
    forceTrigger = isShallow(source)
  } else if (isReactive(source)) {
    // 如果source是reactive类型，getter是个返回source的函数，并将deep设置为true。
    getter = () => source
    deep = true
  } else if (isArray(source)) {
    // 如果source是个数组，将isMultiSource设为true，
    // forceTrigger取决于source是否有reactive类型的数据，
    // getter函数中会遍历source，针对不同类型的source做不同处理。
    isMultiSource = true
    forceTrigger = source.some(isReactive)
    getter = () =>
      source.map(s => {
        if (isRef(s)) {
          return s.value
        } else if (isReactive(s)) {
          return traverse(s)
        } else if (isFunction(s)) {
          return callWithErrorHandling(s, instance, ErrorCodes.WATCH_GETTER)
        } else {
          __DEV__ && warnInvalidSource(s)
        }
      })
  } else if (isFunction(source)) {
    // 如果source是个function。存在cb的情况下，getter函数中会执行source，
    // 这里source会通过callWithErrorHandling函数执行，在callWithErrorHandling中会处理source执行过程中出现的错误；
    // 不存在cb的话，在getter中，如果组件已经被卸载了，直接return，
    // 否则判断cleanup（cleanup是在watchEffect中通过onCleanup注册的清理函数）
    // 如果存在cleanup执行cleanup，接着执行source，并返回执行结果。
    // source会被callWithAsyncErrorHandling包装，
    // 该函数作用会处理source执行过程中出现的错误，与callWithErrorHandling不同的是，
    // callWithAsyncErrorHandling会处理异步错误。
    if (cb) {
      // getter with cb
      getter = () =>
        callWithErrorHandling(source, instance, ErrorCodes.WATCH_GETTER)
    } else {
      // no cb -> simple effect
      getter = () => {
        // 如果组件实例已经卸载，直接return
        if (instance && instance.isUnmounted) {
          return
        }
        // 如果清理函数，则执行清理函数
        if (cleanup) {
          cleanup()
        }
        // 执行source，传入onCleanup，用来注册清理函数
        return callWithAsyncErrorHandling(
          source,
          instance,
          ErrorCodes.WATCH_CALLBACK,
          [onCleanup]
        )
      }
    }
  } else {
    //getter会被赋为一个空函数
    getter = NOOP
    __DEV__ && warnInvalidSource(source)
  }

  // 对vue2的数组的进行兼容性处理
  // 2.x array mutation watch compat
  if (__COMPAT__ && cb && !deep) {
    // 如果存在cb并且deep为true，那么需要对数据进行深度监听，
    // 这时，会重新对getter赋值，在新的getter函数中递归访问之前getter的返回结果。
    const baseGetter = getter
    getter = () => {
      const val = baseGetter()
      if (
        isArray(val) &&
        checkCompatEnabled(DeprecationTypes.WATCH_ARRAY, instance)
      ) {
        //递归遍历所有属性，seen用于防止循环引用问题。
        traverse(val)
      }
      return val
    }
  }

  // getter函数中会尽可能访问响应式数据，尤其是deep为true并存在cb的情况时，
  // 会调用traverse完成对source的递归属性访问）、forceTrigger、isMultiSource已经被确定，
  if (cb && deep) {
    const baseGetter = getter
    getter = () => traverse(baseGetter())
  }

  // 声明了两个变量：cleanup、onCleanup。onCleanup会作为参数传递给watchEffect中的effect函数。
  // 当onCleanup执行时，会将他的参数通过callWithErrorHandling封装赋给cleanup及effect.onStop（effect在后文中创建）。

  let cleanup: () => void
  let onCleanup: OnCleanup = (fn: () => void) => {
    cleanup = effect.onStop = () => {
      callWithErrorHandling(fn, instance, ErrorCodes.WATCH_CLEANUP)
    }
  }

  // in SSR there is no need to setup an actual effect, and it should be noop
  // unless it's eager
  // SSR处理过程
  if (__SSR__ && isInSSRComponentSetup) {
    // we will also not call the invalidate callback (+ runner is not set up)
    onCleanup = NOOP
    if (!cb) {
      getter()
    } else if (immediate) {
      callWithAsyncErrorHandling(cb, instance, ErrorCodes.WATCH_CALLBACK, [
        getter(),
        isMultiSource ? [] : undefined,
        onCleanup
      ])
    }
    return NOOP
  }

  // 声明了一个oldValue和job变量。如果是多数据源oldValue是个数组，否则是个对象。

  // job函数的作用是触发cb(watch)或执行effect.run(watchEffect)。
  // job函数中会首先判断effect的激活状态，如果未激活，则return。
  // 然后判断如果存在cb，调用effet.run获取最新值，下一步就是触发cb
  // 这里触发cb需要满足以下条件的任意一个条件即可：

  // 1.深度监听deep===true
  // 2.强制触发forceTrigger===true
  // 3.如果多数据源，newValue中存在与oldValue中的值不相同的项（利用Object.is判断）；如果不是多数据源，newValue与oldValue不相同。
  // 4.开启了vue2兼容模式，并且newValue是个数组，并且开启了WATCH_ARRAY
  // 只要符合上述条件的任意一条，便可已触发cb，在触发cb之前会先调用cleanup函数。执行完cb后，需要将newValue赋值给oldValue。
  // 如果不存在cb，那么直接调用effect.run即可。

  let oldValue = isMultiSource ? [] : INITIAL_WATCHER_VALUE
  const job: SchedulerJob = () => {
    if (!effect.active) {
      return
    }
    if (cb) {
      // watch(source, cb)
      const newValue = effect.run()
      if (
        deep ||
        forceTrigger ||
        (isMultiSource
          ? (newValue as any[]).some((v, i) =>
              hasChanged(v, (oldValue as any[])[i])
            )
          : hasChanged(newValue, oldValue)) ||
        (__COMPAT__ &&
          isArray(newValue) &&
          isCompatEnabled(DeprecationTypes.WATCH_ARRAY, instance))
      ) {
        // cleanup before running cb again
        if (cleanup) {
          cleanup()
        }
        callWithAsyncErrorHandling(cb, instance, ErrorCodes.WATCH_CALLBACK, [
          newValue,
          // pass undefined as the old value when it's changed for the first time
          oldValue === INITIAL_WATCHER_VALUE ? undefined : oldValue,
          onCleanup
        ])
        oldValue = newValue
      }
    } else {
      // watchEffect
      effect.run()
    }
  }

  // important: mark the job as a watcher callback so that scheduler knows
  // it is allowed to self-trigger (#1727)
  job.allowRecurse = !!cb

  // 声明了一个调度器scheduler，在scheduler中会根据flush的不同决定job的触发时机：
  let scheduler: EffectScheduler
  if (flush === 'sync') {
    scheduler = job as any // the scheduler function gets called directly
  } else if (flush === 'post') {
    // 延迟执行，将job添加到一个延迟队列，这个队列会在组件挂在后、更新的生命周期中执行
    scheduler = () => queuePostRenderEffect(job, instance && instance.suspense)
  } else {
    // default: 'pre'
    // 默认 pre，将job添加到一个优先执行队列，该队列在挂载前执行
    scheduler = () => {
      if (!instance || instance.isMounted) {
        queuePreFlushCb(job)
      } else {
        // with 'pre' option, the first call must happen before
        // the component is mounted so it is called synchronously.
        job()
      }
    }
  }

  // getter与scheduler准备完成，创建effect实例。
  const effect = new ReactiveEffect(getter, scheduler)

  if (__DEV__) {
    effect.onTrack = onTrack
    effect.onTrigger = onTrigger
  }

  // initial run
  //  开始首次执行副作用函数。这里针对不同情况有多个分支：

  // - 如果存在cb的情况
  // - 如果immediate为true，执行job，触发cb
  // - 否则执行effect.run()进行依赖的收集，并将结果赋值给oldValue
  // - 如果flush===post，会将effect.run推入一个延迟队列中
  // - 其他情况，也就是watchEffect，则会执行effect.run进行依赖的收集

  if (cb) {
    if (immediate) {
      job()
    } else {
      oldValue = effect.run()
    }
  } else if (flush === 'post') {
    queuePostRenderEffect(
      effect.run.bind(effect),
      instance && instance.suspense
    )
  } else {
    effect.run()
  }

  // 返回一个函数，这个函数的作用是停止watch对数据源的监听。
  // 在函数内部调用effect.stop()将effect置为失活状态，
  // 如果存在组件实例，并且组件示例中存在effectScope，那么需要将effect从effectScope中移除。
  return () => {
    effect.stop()
    if (instance && instance.scope) {
      remove(instance.scope.effects!, effect)
    }
  }
}

// this.$watch
export function instanceWatch(
  this: ComponentInternalInstance,
  source: string | Function,
  value: WatchCallback | ObjectWatchOptionItem,
  options?: WatchOptions
): WatchStopHandle {
  const publicThis = this.proxy as any
  const getter = isString(source)
    ? source.includes('.')
      ? createPathGetter(publicThis, source)
      : () => publicThis[source]
    : source.bind(publicThis, publicThis)
  let cb
  if (isFunction(value)) {
    cb = value
  } else {
    cb = value.handler as Function
    options = value
  }
  const cur = currentInstance
  setCurrentInstance(this)
  const res = doWatch(getter, cb.bind(publicThis), options)
  if (cur) {
    setCurrentInstance(cur)
  } else {
    unsetCurrentInstance()
  }
  return res
}

export function createPathGetter(ctx: any, path: string) {
  const segments = path.split('.')
  return () => {
    let cur = ctx
    for (let i = 0; i < segments.length && cur; i++) {
      cur = cur[segments[i]]
    }
    return cur
  }
}

// 递归遍历所有属性，seen用于防止循环引用问题
export function traverse(value: unknown, seen?: Set<unknown>) {
  // 如果value不是对象或value不可被转为代理（经过markRaw处理），直接return value
  if (!isObject(value) || (value as any)[ReactiveFlags.SKIP]) {
    return value
  }
  //sean用于暂存访问过的属性，防止出现循环引用引起无限递归
  seen = seen || new Set()
  if (seen.has(value)) {
    // 如果seen中已经存在了value，意味着value中存在循环引用的情况，这时return value
    return value
  }
  // 添加value到seen中
  seen.add(value)
  if (isRef(value)) {
    // 如果是ref，递归访问value.value
    traverse(value.value, seen)
  } else if (isArray(value)) {
    // 如果是数组，遍历数组并调用traverse递归访问元素内的属性
    for (let i = 0; i < value.length; i++) {
      traverse(value[i], seen)
    }
  } else if (isSet(value) || isMap(value)) {
    // 如果是Set或Map，调用traverse递归访问集合中的值
    value.forEach((v: any) => {
      traverse(v, seen)
    })
  } else if (isPlainObject(value)) {
    // 如果是原始对象，调用traverse递归方位value中的属性
    for (const key in value) {
      traverse((value as any)[key], seen)
    }
  }
  // 最后需要返回value
  return value
}
