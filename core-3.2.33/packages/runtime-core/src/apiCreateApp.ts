import {
  ConcreteComponent,
  Data,
  validateComponentName,
  Component,
  ComponentInternalInstance,
  getExposeProxy
} from './component'
import {
  ComponentOptions,
  MergedComponentOptions,
  RuntimeCompilerOptions
} from './componentOptions'
import { ComponentPublicInstance } from './componentPublicInstance'
import { Directive, validateDirectiveName } from './directives'
import { RootRenderFunction } from './renderer'
import { InjectionKey } from './apiInject'
import { warn } from './warning'
import { createVNode, cloneVNode, VNode } from './vnode'
import { RootHydrateFunction } from './hydration'
import { devtoolsInitApp, devtoolsUnmountApp } from './devtools'
import { isFunction, NO, isObject } from '@vue/shared'
import { version } from '.'
import { installAppCompatProperties } from './compat/global'
import { NormalizedPropsOptions } from './componentProps'
import { ObjectEmitsOptions } from './componentEmits'

export interface App<HostElement = any> {
  version: string
  config: AppConfig
  use(plugin: Plugin, ...options: any[]): this
  mixin(mixin: ComponentOptions): this
  component(name: string): Component | undefined
  component(name: string, component: Component): this
  directive(name: string): Directive | undefined
  directive(name: string, directive: Directive): this
  mount(
    rootContainer: HostElement | string,
    isHydrate?: boolean,
    isSVG?: boolean
  ): ComponentPublicInstance
  unmount(): void
  provide<T>(key: InjectionKey<T> | string, value: T): this

  // internal, but we need to expose these for the server-renderer and devtools
  _uid: number
  _component: ConcreteComponent
  _props: Data | null
  _container: HostElement | null
  _context: AppContext
  _instance: ComponentInternalInstance | null

  /**
   * v2 compat only
   */
  filter?(name: string): Function | undefined
  filter?(name: string, filter: Function): this

  /**
   * @internal v3 compat only
   */
  _createRoot?(options: ComponentOptions): ComponentPublicInstance
}

export type OptionMergeFunction = (to: unknown, from: unknown) => any

export interface AppConfig {
  // @private
  readonly isNativeTag?: (tag: string) => boolean

  performance: boolean
  optionMergeStrategies: Record<string, OptionMergeFunction>
  globalProperties: Record<string, any>
  errorHandler?: (
    err: unknown,
    instance: ComponentPublicInstance | null,
    info: string
  ) => void
  warnHandler?: (
    msg: string,
    instance: ComponentPublicInstance | null,
    trace: string
  ) => void

  /**
   * Options to pass to `@vue/compiler-dom`.
   * Only supported in runtime compiler build.
   */
  compilerOptions: RuntimeCompilerOptions

  /**
   * @deprecated use config.compilerOptions.isCustomElement
   */
  isCustomElement?: (tag: string) => boolean

  /**
   * Temporary config for opt-in to unwrap injected refs.
   * TODO deprecate in 3.3
   */
  unwrapInjectedRef?: boolean
}

export interface AppContext {
  app: App // for devtools
  config: AppConfig
  mixins: ComponentOptions[]
  components: Record<string, Component>
  directives: Record<string, Directive>
  provides: Record<string | symbol, any>

  /**
   * Cache for merged/normalized component options
   * Each app instance has its own cache because app-level global mixins and
   * optionMergeStrategies can affect merge behavior.
   * @internal
   */
  optionsCache: WeakMap<ComponentOptions, MergedComponentOptions>
  /**
   * Cache for normalized props options
   * @internal
   */
  propsCache: WeakMap<ConcreteComponent, NormalizedPropsOptions>
  /**
   * Cache for normalized emits options
   * @internal
   */
  emitsCache: WeakMap<ConcreteComponent, ObjectEmitsOptions | null>
  /**
   * HMR only
   * @internal
   */
  reload?: () => void
  /**
   * v2 compat only
   * @internal
   */
  filters?: Record<string, Function>
}

type PluginInstallFunction = (app: App, ...options: any[]) => any

export type Plugin =
  | (PluginInstallFunction & { install?: PluginInstallFunction })
  | {
      install: PluginInstallFunction
    }

export function createAppContext(): AppContext {
  return {
    app: null as any,
    config: {
      isNativeTag: NO, // 一个判断是否为原生标签的函数
      performance: false,
      globalProperties: {},
      optionMergeStrategies: {}, // 自定义options的合并策略
      errorHandler: undefined,
      warnHandler: undefined,
      compilerOptions: {} // 组件模板的运行时编译器选项
    },
    mixins: [], // 存储全局混入的mixin
    components: {}, // 保存全局注册的组件
    directives: {}, // 保存注册的全局指令
    provides: Object.create(null), // 保存全局provide的值
    optionsCache: new WeakMap(), // 缓存组件被解析过的options（合并了全局mixins、extends、局部mixins）
    propsCache: new WeakMap(), // 缓存每个组件经过标准化的的props options
    emitsCache: new WeakMap() // 缓存每个组件经过标准化的的emits options
  }
}

export type CreateAppFunction<HostElement> = (
  rootComponent: Component,
  rootProps?: Data | null
) => App<HostElement>

let uid = 0

export function createAppAPI<HostElement>(
  render: RootRenderFunction,
  hydrate?: RootHydrateFunction
): CreateAppFunction<HostElement> {
  //接受一个根组件参数和一个rootProps（根组件的props）参数。
  return function createApp(rootComponent, rootProps = null) {
    // 如果根组件不是方法时，将rootComponent使用解构的方式重新赋值为一个新的对象
    if (!isFunction(rootComponent)) {
      rootComponent = { ...rootComponent }
    }
    //判断rootProps如果不为null并且也不是个对象，则会将rootProps置为null。
    if (rootProps != null && !isObject(rootProps)) {
      __DEV__ && warn(`root props passed to app.mount() must be an object.`)
      rootProps = null
    }

    // 调用createAppContext()方法创建一个上下文对象
    const context = createAppContext()
    // installedPlugins会用来存储使用use安装的plugin
    const installedPlugins = new Set()
    // isMounted代表根组件是否已经挂载。
    let isMounted = false

    //app变量就是app实例，在创建app的同时会将app添加到上下文中的app属性中。
    const app: App = (context.app = {
      _uid: uid++, //app的唯一标识，每次都会使用uid为新app的唯一标识，在赋值后，uid会进行自增，以便下一个app使用
      _component: rootComponent as ConcreteComponent, //根组件
      _props: rootProps, //根组件所需的props
      _container: null, //需要将根组件渲染到的容器
      _context: context, //app的上下文
      _instance: null, //根组件的实例

      version, //vue的版本

      // 获取上下文中的config
      get config() {
        return context.config
      },

      //拦截app.config的set操作，防止app.config被修改
      set config(v) {
        if (__DEV__) {
          warn(
            `app.config cannot be replaced. Modify individual options instead.`
          )
        }
      },

      // 安装plugin 重复安装多次的plugin，只会安装一次，
      // installedPlugins，每次安装新的plugin后，都会将plugin存入installedPlugins
      use(plugin: Plugin, ...options: any[]) {
        // 如果已经安装过plugin，则不需要再次安装
        if (installedPlugins.has(plugin)) {
          __DEV__ && warn(`Plugin has already been applied to target app.`)
        } else if (plugin && isFunction(plugin.install)) {
          // 如果存在plugin，并且plugin.install是个方法
          installedPlugins.add(plugin)
          plugin.install(app, ...options)
        } else if (isFunction(plugin)) {
          //如果plugin是方法
          installedPlugins.add(plugin)
          plugin(app, ...options)
        } else if (__DEV__) {
          warn(
            `A plugin must either be a function or an object with an "install" ` +
              `function.`
          )
        }
        // 返回app，以便可以链式调用app的方法
        return app
      },

      // 全局混入，被混入的对象会被存在上下文中的mixins中
      // 注意mixin只会在支持options api的版本中才能使用，在mixin中会通过__FEATURE_OPTIONS_API__进行判断，
      // 这个变量会在打包过程中借助@rollup/plugin-replace进行替换。
      mixin(mixin: ComponentOptions) {
        if (__FEATURE_OPTIONS_API__) {
          if (!context.mixins.includes(mixin)) {
            context.mixins.push(mixin)
          } else if (__DEV__) {
            warn(
              'Mixin has already been applied to target app' +
                (mixin.name ? `: ${mixin.name}` : '')
            )
          }
        } else if (__DEV__) {
          warn('Mixins are only available in builds supporting Options API')
        }
        return app
      },

      //全局注册组件，也可用来获取name对应的组件。被注册的组件会被存在上下文中的components中。
      component(name: string, component?: Component): any {
        if (__DEV__) {
          // 验证组件名是否符合要求
          validateComponentName(name, context.config)
        }
        if (!component) {
          // 如果不存在component，那么会返回name对应的组件
          return context.components[name]
        }
        if (__DEV__ && context.components[name]) {
          warn(`Component "${name}" has already been registered in target app.`)
        }
        context.components[name] = component
        return app
      },

      //注册全局指令，也可用来获取name对应的指令对象。注册的全局指令会被存入上下文中的directives中
      directive(name: string, directive?: Directive) {
        if (__DEV__) {
          // 验证指令名称
          validateDirectiveName(name)
        }

        if (!directive) {
          // 如果不存在directive，则返回name对应的指令对象
          return context.directives[name] as any
        }
        if (__DEV__ && context.directives[name]) {
          warn(`Directive "${name}" has already been registered in target app.`)
        }
        context.directives[name] = directive
        return app
      },

      //挂载 createApp会对该方法进行重写扩展
      mount(
        rootContainer: HostElement,
        isHydrate?: boolean,
        isSVG?: boolean
      ): any {
        // 如果未挂载，开始挂载
        if (!isMounted) {
          // 创建根组件的虚拟DOM
          const vnode = createVNode(
            rootComponent as ConcreteComponent,
            rootProps
          )
          // store app context on the root VNode.
          // this will be set on the root instance on initial mount.
          // 将上下文添加到根组件虚拟dom的appContext属性中
          vnode.appContext = context

          // HMR root reload
          if (__DEV__) {
            context.reload = () => {
              render(cloneVNode(vnode), rootContainer, isSVG)
            }
          }

          if (isHydrate && hydrate) {
            // 同构渲染
            hydrate(vnode as VNode<Node, Element>, rootContainer as any)
          } else {
            //客户端渲染
            render(vnode, rootContainer, isSVG)
          }
          // 渲染完成后将isMounted置为true
          isMounted = true
          // 将容器添加到app的_container属性中
          app._container = rootContainer
          // for devtools and telemetry
          // 将rootContainer.__vue_app__指向app实例
          ;(rootContainer as any).__vue_app__ = app

          if (__DEV__ || __FEATURE_PROD_DEVTOOLS__) {
            // 将根组件实例赋给app._instance
            app._instance = vnode.component
            devtoolsInitApp(app, version)
          }
          // 返回根组件expose的属性
          return getExposeProxy(vnode.component!) || vnode.component!.proxy
        } else if (__DEV__) {
          warn(
            `App has already been mounted.\n` +
              `If you want to remount the same app, move your app creation logic ` +
              `into a factory function and create fresh app instances for each ` +
              `mount - e.g. \`const createMyApp = () => createApp(App)\``
          )
        }
      },
      // 卸载应用实例
      unmount() {
        // 如果已经挂载才能进行卸载
        if (isMounted) {
          // 调用redner函数，此时虚拟节点为null，代表会清空容器中的内容
          render(null, app._container)
          if (__DEV__ || __FEATURE_PROD_DEVTOOLS__) {
            // 将app._instance置空
            app._instance = null
            devtoolsUnmountApp(app)
          }
          // 删除容器中的__vue_app__
          delete app._container.__vue_app__
        } else if (__DEV__) {
          warn(`Cannot unmount an app that is not mounted.`)
        }
      },

      // 全局注入一些数据。这些数据会被存入上下文对象的provides中。
      provide(key, value) {
        if (__DEV__ && (key as string | symbol) in context.provides) {
          warn(
            `App already provides property with key "${String(key)}". ` +
              `It will be overwritten with the new value.`
          )
        }
        // TypeScript doesn't allow symbols as index type
        // https://github.com/Microsoft/TypeScript/issues/24587
        context.provides[key as string] = value

        return app
      }
    })

    //vue2的兼容处理
    if (__COMPAT__) {
      installAppCompatProperties(app, context, render)
    }

    return app
  }
}
