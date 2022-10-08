import { TrackOpTypes, TriggerOpTypes } from './operations'
import { extend, isArray, isIntegerKey, isMap } from '@vue/shared'
import { EffectScope, recordEffectScope } from './effectScope'
import {
  createDep,
  Dep,
  finalizeDepMarkers,
  initDepMarkers,
  newTracked,
  wasTracked
} from './dep'
import { ComputedRefImpl } from './computed'

// The main WeakMap that stores {target -> key -> dep} connections.
// Conceptually, it's easier to think of a dependency as a Dep class
// which maintains a Set of subscribers, but we simply store them as
// raw Sets to reduce memory overhead.
type KeyToDepMap = Map<any, Dep>
const targetMap = new WeakMap<any, KeyToDepMap>()

// The number of effects currently being tracked recursively.
let effectTrackDepth = 0

export let trackOpBit = 1

/**
 * The bitwise track markers support at most 30 levels of recursion.
 * This value is chosen to enable modern JS engines to use a SMI on all platforms.
 * When recursion depth is greater, fall back to using a full cleanup.
 */
const maxMarkerBits = 30

export type EffectScheduler = (...args: any[]) => any

export type DebuggerEvent = {
  effect: ReactiveEffect
} & DebuggerEventExtraInfo

export type DebuggerEventExtraInfo = {
  target: object
  type: TrackOpTypes | TriggerOpTypes
  key: any
  newValue?: any
  oldValue?: any
  oldTarget?: Map<any, any> | Set<any>
}

export let activeEffect: ReactiveEffect | undefined

export const ITERATE_KEY = Symbol(__DEV__ ? 'iterate' : '')
export const MAP_KEY_ITERATE_KEY = Symbol(__DEV__ ? 'Map key iterate' : '')

export class ReactiveEffect<T = any> {
  active = true //是否激活
  deps: Dep[] = [] //effect对应的属性
  parent: ReactiveEffect | undefined = undefined

  /**
   * Can be attached after creation
   * @internal
   */
  computed?: ComputedRefImpl<T>
  /**
   * @internal
   */
  allowRecurse?: boolean //允许重复执行
  /**
   * @internal
   */
  private deferStop?: boolean

  onStop?: () => void
  // dev only
  onTrack?: (event: DebuggerEvent) => void
  // dev only
  onTrigger?: (event: DebuggerEvent) => void

  // 构造器可以接受三个参数：fn（副作用函数）、scheduler（调度器）、scope（一个EffectScope作用域对象），
  // 在构造器中调用了一个recordEffectScope方法，这个方法会将当前ReactiveEffect对象（this）放入对应的EffectScope作用域（scope）中。
  constructor(
    public fn: () => T, //原函数
    public scheduler: EffectScheduler | null = null,
    scope?: EffectScope
  ) {
    recordEffectScope(this, scope)
  }

  run() {
    //首先判断ReactiveEffect的激活状态（active），如果未激活（this.active === false），那么会立马执行this.fn并返回他的执行结果
    if (!this.active) {
      return this.fn()
    }
    let parent: ReactiveEffect | undefined = activeEffect
    let lastShouldTrack = shouldTrack
    // 使用while循环寻找parent.parent，一旦parent与this相等，立即结束循环。
    while (parent) {
      if (parent === this) {
        return
      }
      parent = parent.parent
    }

    try {
      // 建立一个嵌套effect的关系
      this.parent = activeEffect
      activeEffect = this
      shouldTrack = true

      // effectTrackDepth是个全局变量为effect的深度，层数从1开始计数，
      // trackOpBit使用二进制标记依赖收集的状态（如00000000000000000000000000000010表示所处深度为1）
      trackOpBit = 1 << ++effectTrackDepth

      // 如果effectTrackDepth未超出最大标记位（maxMarkerBits = 30），
      // 会调用initDepMarkers方法将this.deps中的所有dep标记为已经被track的状态；
      // 否则使用cleanupEffect移除deps中的所有dep。

      //标记dep为已被track或移除dep的作用就是移除多余的依赖,比如三目运算造成的分支切换
      if (effectTrackDepth <= maxMarkerBits) {
        // 将依赖标记为已收集
        initDepMarkers(this)
      } else {
        cleanupEffect(this)
      }
      return this.fn()
    } finally {
      //根据一些状态移除多余的依赖、将effectTrackDepth回退一层，
      // activeEffect指向当前ReactiveEffect的parent、shouldTrack = lastShouldTrack、this.parent置为undefined
      if (effectTrackDepth <= maxMarkerBits) {
        finalizeDepMarkers(this)
      }

      trackOpBit = 1 << --effectTrackDepth

      activeEffect = this.parent
      shouldTrack = lastShouldTrack
      this.parent = undefined

      if (this.deferStop) {
        this.stop()
      }
    }
  }

  stop() {
    // stopped while running itself - defer the cleanup
    if (activeEffect === this) {
      this.deferStop = true
    } else if (this.active) {
      cleanupEffect(this)
      if (this.onStop) {
        this.onStop()
      }
      this.active = false
    }
  }
}

// 清除依赖
function cleanupEffect(effect: ReactiveEffect) {
  const { deps } = effect
  if (deps.length) {
    for (let i = 0; i < deps.length; i++) {
      deps[i].delete(effect)
    }
    deps.length = 0
  }
}

export interface DebuggerOptions {
  onTrack?: (event: DebuggerEvent) => void
  onTrigger?: (event: DebuggerEvent) => void
}

export interface ReactiveEffectOptions extends DebuggerOptions {
  lazy?: boolean
  scheduler?: EffectScheduler
  scope?: EffectScope
  allowRecurse?: boolean
  onStop?: () => void
}

export interface ReactiveEffectRunner<T = any> {
  (): T
  effect: ReactiveEffect
}

// effect可以接收两个参数，其中第二个参数为可选参数，可以不传。第一个参数是一个副作用函数fn，第二个参数是个对象，该对象可以有如下属性：

// lazy：boolean，是否懒加载，如果是true，调用effect不会立即执行监听函数，需要用户手动执行
// scheduler：一个调度函数，如果存在调度函数，在触发依赖时，执行该调度函数
// scope：一个EffectScope作用域对象
// allowRecurse：boolean，允许递归
// onStop：effect被停止时的钩子
export function effect<T = any>(
  fn: () => T,
  options?: ReactiveEffectOptions
): ReactiveEffectRunner {
  // 如果存在fn.effect，那么说明fn已经被effect处理过了，然后使用fn.effect.fn作为fn,原函数
  if ((fn as ReactiveEffectRunner).effect) {
    fn = (fn as ReactiveEffectRunner).effect.fn
  }

  const _effect = new ReactiveEffect(fn)
  // 如果存在option对象的话，会将options，合并到_effect中。
  // 如果存在options.scope，会调用recordEffectScope将_effect放入options.scope。
  // 如果不存在options或options.lazy === false，那么会执行_effect.run()，进行依赖收集。
  if (options) {
    extend(_effect, options)
    if (options.scope) recordEffectScope(_effect, options.scope)
  }
  if (!options || !options.lazy) {
    _effect.run()
  }

  //将_effect.run中的this指向它本身，这样做的目的是用户在主动执行runner时，this指针指向的是_effect对象，
  //然后将_effect作为runner的effect属性，并将runner返回。
  const runner = _effect.run.bind(_effect) as ReactiveEffectRunner
  runner.effect = _effect
  return runner
}

export function stop(runner: ReactiveEffectRunner) {
  runner.effect.stop()
}

export let shouldTrack = true
const trackStack: boolean[] = []

export function pauseTracking() {
  trackStack.push(shouldTrack)
  shouldTrack = false
}

export function enableTracking() {
  trackStack.push(shouldTrack)
  shouldTrack = true
}

export function resetTracking() {
  const last = trackStack.pop()
  shouldTrack = last === undefined ? true : last
}

// target（响应式对象的原始对象）
// type（触发依赖操作的方式，有三种取值：TrackOpTypes.GET、TrackOpTypes.HAS、TrackOpTypes.ITERATE）
// key（触发依赖收集的key）
export function track(target: object, type: TrackOpTypes, key: unknown) {
  //只有shouldTrack为true且存在activeEffect时才可以进行依赖收集
  if (shouldTrack && activeEffect) {
    let depsMap = targetMap.get(target)
    if (!depsMap) {
      targetMap.set(target, (depsMap = new Map()))
    }
    let dep = depsMap.get(key)
    if (!dep) {
      depsMap.set(key, (dep = createDep()))
    }

    const eventInfo = __DEV__
      ? { effect: activeEffect, target, type, key }
      : undefined

    trackEffects(dep, eventInfo)
  }
}

export function trackEffects(
  dep: Dep,
  debuggerEventExtraInfo?: DebuggerEventExtraInfo
) {
  let shouldTrack = false
  if (effectTrackDepth <= maxMarkerBits) {
    //根据tracked标识判断是否进行依赖收集

    // 如果newTracked(dep) === true，说明在本次run方法执行过程中，dep已经被收集过了，shouldTrack不变；
    // 如果newTracked(dep) === false，要把dep标记为新收集的，虽然dep在本次收集过程中是新收集的，
    // 但它可能在之前的收集过程中已经被收集了，所以shouldTrack的值取决于dep是否在之前已经被收集过了。

    if (!newTracked(dep)) {
      dep.n |= trackOpBit // set newly tracked
      shouldTrack = !wasTracked(dep)
    }
  } else {
    // Full cleanup mode.
    // 判断dep中是否含有activeEffect
    shouldTrack = !dep.has(activeEffect!)
  }

  //将activeEffect添加到dep中，同时将dep放入activeEffect.deps中
  if (shouldTrack) {
    dep.add(activeEffect!)
    activeEffect!.deps.push(dep)
    if (__DEV__ && activeEffect!.onTrack) {
      activeEffect!.onTrack({
        effect: activeEffect!,
        ...debuggerEventExtraInfo!
      })
    }
  }
}

/**
target：响应式数据的原始对象
type：操作类型。是个枚举类TriggerOpTypes，共有四种操作类型：
TriggerOpTypes.SET：如obj.xx = xx（修改属性）、map.set(xx, xx)（修改操作不是新增操作）、arr[index] = xx(index < arr.length)、arr.length = 0
TriggerOpTypes.ADD：如obj.xx = xx（新增属性）、set.add(xx)、map.set(xx, xx)（新增操作）、arr[index] = xx(index >= arr.length)
TriggerOpTypes.DELETE：如delete obj.xx、set/map.delete(xx)
TriggerOpTypes.CLEAR：如map/set.clear()
key：可选，触发trigger的键，如obj.foo = 1，key为foo。
newValue：可选，新的值，如obj.foo = 1，newValue为1。
oldValue：可选，旧的值，如obj.foo = 1，oldValue为修改前的obj.foo。
oldTarget：可选，旧的原始对象，只在开发模式下有用。
*/
export function trigger(
  target: object,
  type: TriggerOpTypes,
  key?: unknown,
  newValue?: unknown,
  oldValue?: unknown,
  oldTarget?: Map<unknown, unknown> | Set<unknown>
) {
  //没有依赖 直接返回
  const depsMap = targetMap.get(target)
  if (!depsMap) {
    // never been tracked
    return
  }

  let deps: (Dep | undefined)[] = []
  if (type === TriggerOpTypes.CLEAR) {
    // collection being cleared
    // trigger all effects for target
    deps = [...depsMap.values()]
  } else if (key === 'length' && isArray(target)) {
    depsMap.forEach((dep, key) => {
      if (key === 'length' || key >= (newValue as number)) {
        deps.push(dep)
      }
    })
  } else {
    // schedule runs for SET | ADD | DELETE
    if (key !== void 0) {
      deps.push(depsMap.get(key))
    }

    // also run for iteration key on ADD | DELETE | Map.SET
    switch (type) {
      case TriggerOpTypes.ADD:
        if (!isArray(target)) {
          deps.push(depsMap.get(ITERATE_KEY))
          if (isMap(target)) {
            deps.push(depsMap.get(MAP_KEY_ITERATE_KEY))
          }
        } else if (isIntegerKey(key)) {
          // new index added to array -> length changes
          deps.push(depsMap.get('length'))
        }
        break
      case TriggerOpTypes.DELETE:
        if (!isArray(target)) {
          deps.push(depsMap.get(ITERATE_KEY))
          if (isMap(target)) {
            deps.push(depsMap.get(MAP_KEY_ITERATE_KEY))
          }
        }
        break
      case TriggerOpTypes.SET:
        if (isMap(target)) {
          deps.push(depsMap.get(ITERATE_KEY))
        }
        break
    }
  }

  const eventInfo = __DEV__
    ? { target, type, key, newValue, oldValue, oldTarget }
    : undefined

  if (deps.length === 1) {
    if (deps[0]) {
      if (__DEV__) {
        triggerEffects(deps[0], eventInfo)
      } else {
        triggerEffects(deps[0])
      }
    }
  } else {
    const effects: ReactiveEffect[] = []
    for (const dep of deps) {
      if (dep) {
        effects.push(...dep)
      }
    }
    if (__DEV__) {
      triggerEffects(createDep(effects), eventInfo)
    } else {
      triggerEffects(createDep(effects))
    }
  }
}

export function triggerEffects(
  dep: Dep | ReactiveEffect[],
  debuggerEventExtraInfo?: DebuggerEventExtraInfo
) {
  // spread into array for stabilization
  for (const effect of isArray(dep) ? dep : [...dep]) {
    if (effect !== activeEffect || effect.allowRecurse) {
      if (__DEV__ && effect.onTrigger) {
        effect.onTrigger(extend({ effect }, debuggerEventExtraInfo))
      }
      if (effect.scheduler) {
        effect.scheduler()
      } else {
        effect.run()
      }
    }
  }
}
