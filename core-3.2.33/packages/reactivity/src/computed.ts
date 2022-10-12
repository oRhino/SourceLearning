import { DebuggerOptions, ReactiveEffect } from './effect'
import { Ref, trackRefValue, triggerRefValue } from './ref'
import { isFunction, NOOP } from '@vue/shared'
import { ReactiveFlags, toRaw } from './reactive'
import { Dep } from './dep'

declare const ComputedRefSymbol: unique symbol

export interface ComputedRef<T = any> extends WritableComputedRef<T> {
  readonly value: T
  [ComputedRefSymbol]: true
}

export interface WritableComputedRef<T> extends Ref<T> {
  readonly effect: ReactiveEffect<T>
}

export type ComputedGetter<T> = (...args: any[]) => T
export type ComputedSetter<T> = (v: T) => void

export interface WritableComputedOptions<T> {
  get: ComputedGetter<T>
  set: ComputedSetter<T>
}

export class ComputedRefImpl<T> {
  public dep?: Dep = undefined
  // 缓存的值
  private _value!: T
  // 在构造器中创建的ReactiveEffect实例
  public readonly effect: ReactiveEffect<T>
  // 标记为一个ref类型
  public readonly __v_isRef = true
  // 只读标识
  public readonly [ReactiveFlags.IS_READONLY]: boolean
  // 是否为脏数据，如果是脏数据需要重新计算
  public _dirty = true
  // 是否可缓存，取决于SSR
  public _cacheable: boolean

  // getter、setter、isReadonly（是否只读）、isSSR（是否为SSR）。
  constructor(
    getter: ComputedGetter<T>,
    private readonly _setter: ComputedSetter<T>,
    isReadonly: boolean,
    isSSR: boolean
  ) {
    // 声明了一个ReactiveEffect，并将getter和一个调度函数作为参数传入，
    // 在调度器中如果_dirty为false，会将_dirty设置为true，并执行triggerRefValue函数。
    this.effect = new ReactiveEffect(getter, () => {
      if (!this._dirty) {
        this._dirty = true
        //触发依赖
        triggerRefValue(this)
      }
    })
    // this.effect.computed指向this
    this.effect.computed = this
    // this.effect.active与this._cacheable在SSR中为false
    this.effect.active = this._cacheable = !isSSR
    this[ReactiveFlags.IS_READONLY] = isReadonly
  }

  get value() {
    // the computed ref may get wrapped by other proxies e.g. readonly() #3376
    // computed可能被其他proxy包裹，如readonly(computed(() => foo.bar))，所以要获取this的原始对象
    //// computed可能被其他proxy包裹，如readonly(computed(() => foo.bar))，所以要获取this的原始对象
    const self = toRaw(this)
    //收集依赖
    trackRefValue(self)
    // 如果是脏数据或者是SSR，需要重新计算
    if (self._dirty || !self._cacheable) {
      // _dirty取false，防止依赖不变重复计算
      self._dirty = false
      // 计算
      self._value = self.effect.run()!
    }
    return self._value
  }

  set value(newValue: T) {
    this._setter(newValue)
  }
}

//接受一个getter函数，并以getter函数的返回值返回一个不可变的响应式ref对象。
//或者它也可以使用具有get和set函数的对象来创建一个可写的ref对象。
export function computed<T>(
  getter: ComputedGetter<T>,
  debugOptions?: DebuggerOptions
): ComputedRef<T>
export function computed<T>(
  options: WritableComputedOptions<T>,
  debugOptions?: DebuggerOptions
): WritableComputedRef<T>

/**
 *  computed
 * @param getterOrOptions  一个getter函数，或者包含get、set的对象
 * @param debugOptions 只在开发环境中起作用,包含依赖收集和触发依赖的钩子函数的对象
 * @param isSSR
 * @returns
 */
export function computed<T>(
  getterOrOptions: ComputedGetter<T> | WritableComputedOptions<T>,
  debugOptions?: DebuggerOptions,
  isSSR = false
) {
  let getter: ComputedGetter<T>
  let setter: ComputedSetter<T>

  const onlyGetter = isFunction(getterOrOptions)
  //函数 说明只有getter,只读
  if (onlyGetter) {
    getter = getterOrOptions
    setter = __DEV__
      ? () => {
          console.warn('Write operation failed: computed value is readonly')
        }
      : NOOP
  } else {
    //对象
    getter = getterOrOptions.get
    setter = getterOrOptions.set
  }
  ///返回
  const cRef = new ComputedRefImpl(getter, setter, onlyGetter || !setter, isSSR)

  if (__DEV__ && debugOptions && !isSSR) {
    cRef.effect.onTrack = debugOptions.onTrack
    cRef.effect.onTrigger = debugOptions.onTrigger
  }

  return cRef as any
}
