# cocoapods-meitu-bin

## 简介

`cocoapods-meitu-bin`是`CocoaPods`的二进制插件，提供了二进制相关的功能，如基于壳工程的二进制制作、二进制 / 源码切换等

[美图秀秀 iOS 客户端二进制之路](https://juejin.cn/post/7175023366783385659)

## 安装

`cocoapods-meitu-bin`有2种安装方式：

* 安装到本机目录
* 使用`Gemfile`

### 安装到本机目录

```shell
$ sudo gem install cocoapods-meitu-bin
```
    
### 使用Gemfile

在`Gemfile`中添加如下代码，然后执行`bundle install`

```ruby
gem 'cocoapods-meitu-bin'
```

## 使用

### 制作二进制

进入`Podfile`所在目录，执行`pod bin build-all`即可，根据需要添加相应的`option`选项，支持的`option`选项如下：

| 选项 | 含义 |
|---|---|
| `--clean` | 全部二进制包制作完成后删除编译临时目录 |
| `--clean-single` | 每制作完一个二进制包就删除该编译临时目录 |
| `--repo-update` | 更新`Podfile`中指定的`repo`仓库 |
| `--full-build` | 是否全量编译 |
| `--skip-simulator` | 是否跳过模拟器编译 |
| `--configuration=configName` | 在构建每个目标时使用`configName`指定构建配置，如：`Debug`、`Release`等 |

> 如果想查看详细信息，可以使用`pod bin build-all --help`来查看帮助文档

### 使用二进制

在`Podfile`中添加如下代码，然后执行`pod install`即可

```ruby
# 加载插件
plugin 'cocoapods-meitu-bin'
# 开启二进制
use_binaries!
# 设置源码白名单
set_use_source_pods ['AFNetworking']
```
