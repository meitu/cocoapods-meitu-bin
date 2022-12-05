require 'cocoapods-mtxx-bin/command/bin/init'
# require 'cocoapods-mtxx-bin/command/bin/archive'
# require 'cocoapods-mtxx-bin/command/bin/auto'
# require 'cocoapods-mtxx-bin/command/bin/code'
# require 'cocoapods-mtxx-bin/command/bin/update'
# require 'cocoapods-mtxx-bin/command/bin/install'
require 'cocoapods-mtxx-bin/command/bin/repo'
require 'cocoapods-mtxx-bin/command/bin/spec'
require 'cocoapods-mtxx-bin/command/bin/build_all'
require 'cocoapods-mtxx-bin/command/bin/output_source'
require 'cocoapods-mtxx-bin/command/bin/header_files_specifications'
require 'cocoapods-mtxx-bin/command/bin/upload'
require 'cocoapods-mtxx-bin/command/bin/lock'
require 'cocoapods-mtxx-bin/command/bin/source'
require 'cocoapods-mtxx-bin/helpers'
require 'cocoapods-mtxx-bin/helpers/framework_builder'

module Pod
  class Command
    # This is an example of a cocoapods plugin adding a top-level subcommand
    # to the 'pod' command.
    #
    # You can also create subcommands of existing or new commands. Say you
    # wanted to add a subcommand to `list` to show newly deprecated pods,
    # (e.g. `pod list deprecated`), there are a few things that would need
    # to change.
    #
    # - move this file to `lib/pod/command/list/deprecated.rb` and update
    #   the class to exist in the the Pod::Command::List namespace
    # - change this class to extend from `List` instead of `Command`. This
    #   tells the plugin system that it is a subcommand of `list`.
    # - edit `lib/cocoapods_plugins.rb` to require this file
    #
    # @todo Create a PR to add your plugin to CocoaPods/cocoapods.org
    #       in the `plugins.json` file, once your plugin is released.
    #
    class Bin < Command
      include CBin::SourcesHelper
      include CBin::SpecFilesHelper

      self.abstract_command = true

      # self.default_subcommand = 'open'
      self.summary = '组件二进制化插件'
      # self.description = <<-DESC.strip_heredoc
      #   组件二进制化插件
      #
      #   利用源码私有源与二进制私有源实现对组件依赖类型的切换
      # DESC

      def initialize(argv)
        # ！！！ 下面这个require必须放在这里，不能放到文件顶部，切记 ！！！
        require 'cocoapods-mtxx-bin/native'

        # @help = argv.flag?('help')
        super
        # @env = argv.option('env') || 'dev'
        # CBin.config.set_configuration_env(@env)
        # msg = "cocoapods-mtxx-bin #{CBin::VERSION} 版本 #{@env} 环境"
        # UI.info "\033[44;30m#{msg}\033[0m\n"
      end

      # def validate!
      #   super
      #   banner! if @help
      # end
    end
  end
end