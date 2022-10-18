import { ErrorCodes, callWithErrorHandling } from './errorHandling'
import { isArray, NOOP } from '@vue/shared'
import { ComponentInternalInstance, getComponentName } from './component'
import { warn } from './warning'

export interface SchedulerJob extends Function {
  id?: number
  active?: boolean
  computed?: boolean
  /**
   * Indicates whether the effect is allowed to recursively trigger itself
   * when managed by the scheduler.
   *
   * By default, a job cannot trigger itself because some built-in method calls,
   * e.g. Array.prototype.push actually performs reads as well (#1740) which
   * can lead to confusing infinite loops.
   * The allowed cases are component update functions and watch callbacks.
   * Component update functions may update child component props, which in turn
   * trigger flush: "pre" watch callbacks that mutates state that the parent
   * relies on (#1801). Watch callbacks doesn't track its dependencies so if it
   * triggers itself again, it's likely intentional and it is the user's
   * responsibility to perform recursive state mutation that eventually
   * stabilizes (#1727).
   */
  allowRecurse?: boolean
  /**
   * Attached by renderer.ts when setting up a component's render effect
   * Used to obtain component information when reporting max recursive updates.
   * dev only.
   */
  ownerInstance?: ComponentInternalInstance
}

export type SchedulerJobs = SchedulerJob | SchedulerJob[]

let isFlushing = false
let isFlushPending = false

// 在scheduler中主要通过三个队列实现任务调度，这三个对列分别为：

// pendingPreFlushCbs：组件更新前置任务队列
// queue：组件更新任务队列
// pendingPostFlushCbs：组件更新后置任务队列

// 三个队列的特点：

//               pendingPreFlushCbs	             queue	                            pendingPostFlushCbs
// 执行时机	          DOM更新前	          queue中的job就包含组件的更新	                       DOM更新后
// 是否允许插队	        不允许	                    允许	                                     不允许
// job执行顺序	 按入队顺序执行，先进先出	   按job.id升序顺序执行job。保证父子组件的更新顺序	  按job.id升序顺序执行job

const queue: SchedulerJob[] = []
let flushIndex = 0

const pendingPreFlushCbs: SchedulerJob[] = []
let activePreFlushCbs: SchedulerJob[] | null = null
let preFlushIndex = 0

const pendingPostFlushCbs: SchedulerJob[] = []
let activePostFlushCbs: SchedulerJob[] | null = null
let postFlushIndex = 0

const resolvedPromise = /*#__PURE__*/ Promise.resolve() as Promise<any>
let currentFlushPromise: Promise<void> | null = null

let currentPreFlushParentJob: SchedulerJob | null = null

const RECURSION_LIMIT = 100
type CountMap = Map<SchedulerJob, number>

// nextTick会在flushJobs执行完成后才会执行，
// 组件的更新及onUpdated、onMounted等某些生命周期钩子会在nextTick之前执行。
// 所以在nextTick.then中可以获取到最新的DOM。
export function nextTick<T = void>(
  this: T,
  fn?: (this: T) => void
): Promise<void> {
  const p = currentFlushPromise || resolvedPromise
  return fn ? p.then(this ? fn.bind(this) : fn) : p
}

// #2768
// Use binary-search to find a suitable position in the queue,
// so that the queue maintains the increasing order of job's id,
// which can prevent the job from being skipped and also can avoid repeated patching.
function findInsertionIndex(id: number) {
  // the start index should be `flushIndex + 1`
  let start = flushIndex + 1
  let end = queue.length

  while (start < end) {
    const middle = (start + end) >>> 1
    const middleJobId = getId(queue[middle])
    middleJobId < id ? (start = middle + 1) : (end = middle)
  }

  return start
}
// queue队列入队
export function queueJob(job: SchedulerJob) {
  // the dedupe search uses the startIndex argument of Array.includes()
  // by default the search index includes the current job that is being run
  // so it cannot recursively trigger itself again.
  // if the job is a watch() callback, the search will start with a +1 index to
  // allow it recursively trigger itself - it is the user's responsibility to
  // ensure it doesn't end up in an infinite loop.
  // 当满足以下情况中的一种才可以入队
  // 1. queue长度为0
  // 2. queue中不存在job（如果job是watch()回调，搜索从flushIndex + 1开始，
  // 否则从flushIndex开始），并且job不等于currentPreFlushParentJob
  if (
    (!queue.length ||
      !queue.includes(
        job,
        isFlushing && job.allowRecurse ? flushIndex + 1 : flushIndex
      )) &&
    job !== currentPreFlushParentJob
  ) {
    // job.id为null直接入队
    if (job.id == null) {
      queue.push(job)
    } else {
      // 插队，插队后queue索引区间[flushIndex + 1, end]内的job.id是非递减的
      // findInsertionIndex方法通过二分法寻找[flushIndex + 1, end]区间内大于等于job.id的第一个索引
      queue.splice(findInsertionIndex(job.id), 0, job)
    }
    queueFlush()
  }
}

function queueFlush() {
  // isFlushing表示是否正在执行队列
  // isFlushPending表示是否正在等待执行队列
  // 如果此时未在执行队列也没有正在等待执行队列，则需要将isFlushPending设置为true，表示队列进入等待执行状态
  // 同时在下一个微任务队列执行flushJobs，即在下一个微任务队列执行队列
  if (!isFlushing && !isFlushPending) {
    isFlushPending = true
    currentFlushPromise = resolvedPromise.then(flushJobs)
  }
  // 微任务比宏任务有更高的优先级，当同时存在宏任务和微任务时，会先执行全部的微任务，
  // 然后再执行宏任务，这说明通过微任务，可以将flushJobs尽可能的提前执行。
  // 如果使用宏任务，如果在queueJob之前有多个宏任务，则必须等待这些宏任务执行完后，
  // 才能执行queueJob，这样以来flushJobs的执行就会非常靠后。
}

export function invalidateJob(job: SchedulerJob) {
  const i = queue.indexOf(job)
  if (i > flushIndex) {
    queue.splice(i, 1)
  }
}

function queueCb(
  cb: SchedulerJobs,
  activeQueue: SchedulerJob[] | null,
  pendingQueue: SchedulerJob[],
  index: number
) {
  // 如果cb不是数组
  if (!isArray(cb)) {
    // 激活队列为空或cb不在激活队列中，需要将cb添加到对应队列中
    if (
      !activeQueue ||
      !activeQueue.includes(cb, cb.allowRecurse ? index + 1 : index)
    ) {
      pendingQueue.push(cb)
    }
  } else {
    // 如果 cb 是一个数组，那么它是一个组件生命周期钩子
    // 其已经被去重了，因此我们可以在此处跳过重复检查以提高性能
    // if cb is an array, it is a component lifecycle hook which can only be
    // triggered by a job, which is already deduped in the main queue, so
    // we can skip duplicate check here to improve perf
    pendingQueue.push(...cb)
  }
  queueFlush()
}
// 前置任务队列入队
export function queuePreFlushCb(cb: SchedulerJob) {
  queueCb(cb, activePreFlushCbs, pendingPreFlushCbs, preFlushIndex)
}
// 后置任务队列入队
export function queuePostFlushCb(cb: SchedulerJobs) {
  queueCb(cb, activePostFlushCbs, pendingPostFlushCbs, postFlushIndex)
}

// 用来执行pendingPreFlushCbs中的job。
export function flushPreFlushCbs(
  seen?: CountMap,
  parentJob: SchedulerJob | null = null
) {
  // 有job才执行
  if (pendingPreFlushCbs.length) {
    // 赋值父job
    currentPreFlushParentJob = parentJob
    // 去重并将队列赋值给activePreFlushCbs
    activePreFlushCbs = [...new Set(pendingPreFlushCbs)]
    // 清空pendingPreFlushCbs
    pendingPreFlushCbs.length = 0
    if (__DEV__) {
      seen = seen || new Map()
    }
    // 循环执行job
    for (
      preFlushIndex = 0;
      preFlushIndex < activePreFlushCbs.length;
      preFlushIndex++
    ) {
      if (
        __DEV__ &&
        checkRecursiveUpdates(seen!, activePreFlushCbs[preFlushIndex])
      ) {
        continue
      }
      activePreFlushCbs[preFlushIndex]()
    }
    // 执行完毕后将activePreFlushCbs重置为null、preFlushIndex重置为0、currentPreFlushParentJob重置为null
    activePreFlushCbs = null
    preFlushIndex = 0
    currentPreFlushParentJob = null
    // recursively flush until it drains
    // 递归flushPreFlushCbs，直到pendingPreFlushCbs为空停止
    flushPreFlushCbs(seen, parentJob)
  }
}

export function flushPostFlushCbs(seen?: CountMap) {
  // 存在job才执行
  if (pendingPostFlushCbs.length) {
    // 去重
    const deduped = [...new Set(pendingPostFlushCbs)]
    // 清空pendingPostFlushCbs
    pendingPostFlushCbs.length = 0

    // #1947 already has active queue, nested flushPostFlushCbs call
    // 已经存在activePostFlushCbs，嵌套flushPostFlushCbs调用，直接return
    if (activePostFlushCbs) {
      activePostFlushCbs.push(...deduped)
      return
    }

    activePostFlushCbs = deduped
    if (__DEV__) {
      seen = seen || new Map()
    }
    // 按job.id升序
    activePostFlushCbs.sort((a, b) => getId(a) - getId(b))
    // 循环执行job
    for (
      postFlushIndex = 0;
      postFlushIndex < activePostFlushCbs.length;
      postFlushIndex++
    ) {
      if (
        __DEV__ &&
        checkRecursiveUpdates(seen!, activePostFlushCbs[postFlushIndex])
      ) {
        continue
      }
      activePostFlushCbs[postFlushIndex]()
    }
    // 重置activePostFlushCbs及、postFlushIndex
    activePostFlushCbs = null
    postFlushIndex = 0
  }
}

const getId = (job: SchedulerJob): number =>
  job.id == null ? Infinity : job.id

// 在flushJobs中会依次执行pendingPreFlushCbs、queue、pendingPostFlushCbs中的任务，
// 如果此时还有剩余job，则继续执行flushJobs，直到将三个队列中的任务都执行完。
function flushJobs(seen?: CountMap) {
  // 将isFlushPending置为false，isFlushing置为true
  // 因为此时已经要开始执行队列了
  isFlushPending = false
  isFlushing = true
  if (__DEV__) {
    seen = seen || new Map()
  }
  // 执行前置任务队列
  flushPreFlushCbs(seen)

  // Sort queue before flush.
  // This ensures that:
  // 1. Components are updated from parent to child. (because parent is always
  //    created before the child so its render effect will have smaller
  //    priority number)
  // 2. If a component is unmounted during a parent component's update,
  //    its update can be skipped.
  // queue按job.id升序排列
  // 这可确保：
  // 1. 组件从父组件先更新然后子组件更新。（因为 parent 总是在 child 之前创建，所以它的redner effect会具有较高的优先级）
  // 2. 如果在 parent 组件更新期间卸载组件，则可以跳过其更新
  queue.sort((a, b) => getId(a) - getId(b))

  // conditional usage of checkRecursiveUpdate must be determined out of
  // try ... catch block since Rollup by default de-optimizes treeshaking
  // inside try-catch. This can leave all warning code unshaked. Although
  // they would get eventually shaken by a minifier like terser, some minifiers
  // would fail to do that (e.g. https://github.com/evanw/esbuild/issues/1610)
  // 用于检测是否是无限递归，最多 100 层递归，否则就报错，只会开发模式下检查
  const check = __DEV__
    ? (job: SchedulerJob) => checkRecursiveUpdates(seen!, job)
    : NOOP

  // 执行queue中的任务
  try {
    for (flushIndex = 0; flushIndex < queue.length; flushIndex++) {
      const job = queue[flushIndex]
      if (job && job.active !== false) {
        if (__DEV__ && check(job)) {
          continue
        }
        // console.log(`running:`, job.id)
        callWithErrorHandling(job, null, ErrorCodes.SCHEDULER)
      }
    }
  } finally {
    // 清空queue并将flushIndex重置为0
    flushIndex = 0
    queue.length = 0

    // 执行后置任务队列
    flushPostFlushCbs(seen)

    // 将isFlushing置为false，说明此时任务已经执行完
    isFlushing = false
    currentFlushPromise = null
    // some postFlushCb queued jobs!
    // keep flushing until it drains.
    // 执行剩余job
    // post队列执行过程中可能有job加入，继续调用flushJobs执行剩余job
    if (
      queue.length ||
      pendingPreFlushCbs.length ||
      pendingPostFlushCbs.length
    ) {
      flushJobs(seen)
    }
  }
}

function checkRecursiveUpdates(seen: CountMap, fn: SchedulerJob) {
  if (!seen.has(fn)) {
    seen.set(fn, 1)
  } else {
    const count = seen.get(fn)!
    if (count > RECURSION_LIMIT) {
      const instance = fn.ownerInstance
      const componentName = instance && getComponentName(instance.type)
      warn(
        `Maximum recursive updates exceeded${
          componentName ? ` in component <${componentName}>` : ``
        }. ` +
          `This means you have a reactive effect that is mutating its own ` +
          `dependencies and thus recursively triggering itself. Possible sources ` +
          `include component template, render function, updated hook or ` +
          `watcher source function.`
      )
      return true
    } else {
      seen.set(fn, count + 1)
    }
  }
}
