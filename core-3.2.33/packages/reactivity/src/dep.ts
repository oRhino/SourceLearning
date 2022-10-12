import { ReactiveEffect, trackOpBit } from './effect'

export type Dep = Set<ReactiveEffect> & TrackedMarkers

/**
 * wasTracked and newTracked maintain the status for several levels of effect
 * tracking recursion. One bit per level is used to define whether the dependency
 * was/is tracked.
 */
type TrackedMarkers = {
  /**
   * wasTracked 表示是否已经被收集
   */
  w: number
  /**
   * newTracked 表示是否新收集
   */
  n: number
}

export const createDep = (effects?: ReactiveEffect[]): Dep => {
  const dep = new Set<ReactiveEffect>(effects) as Dep
  dep.w = 0
  dep.n = 0
  return dep
}
// wasTracked(dep)返回true，意味着dep在之前的依赖收集过程中已经被收集过，或者说在之前run执行过程中已经被收集
export const wasTracked = (dep: Dep): boolean => (dep.w & trackOpBit) > 0
// newTracked(dep)返回true，意味着dep是在本次依赖收集过程中新收集到的，或者说在本次run执行过程中新收集到的
export const newTracked = (dep: Dep): boolean => (dep.n & trackOpBit) > 0

export const initDepMarkers = ({ deps }: ReactiveEffect) => {
  if (deps.length) {
    for (let i = 0; i < deps.length; i++) {
      deps[i].w |= trackOpBit // set was tracked
    }
  }
}

//找到那些曾经被收集过但是新的一轮依赖收集没有被收集的依赖，从 deps 中移除。
// 其实就是解决需要 cleanup 场景的问题：
// 在新的组件渲染过程中没有访问到的响应式对象，那么它的变化不应该触发组件的重新渲染。
export const finalizeDepMarkers = (effect: ReactiveEffect) => {
  const { deps } = effect
  if (deps.length) {
    let ptr = 0
    for (let i = 0; i < deps.length; i++) {
      const dep = deps[i]
      // 曾经被收集过但不是新的依赖，需要删除
      if (wasTracked(dep) && !newTracked(dep)) {
        dep.delete(effect)
      } else {
        deps[ptr++] = dep
      }
      // clear bits
      // 清空状态
      dep.w &= ~trackOpBit
      dep.n &= ~trackOpBit
    }
    deps.length = ptr
  }
}

// 相比于之前每次执行 effect 函数都需要先清空依赖，再添加依赖的过程，
// 现在的实现会在每次执行 effect 包裹的函数前标记依赖的状态，
// 过程中对于已经收集的依赖不会重复收集，
// 执行完 effect 函数还会移除掉已被收集但是新的一轮依赖收集中没有被收集的依赖。
// 优化后对于 dep 依赖集合的操作减少了，自然也就优化了性能。
