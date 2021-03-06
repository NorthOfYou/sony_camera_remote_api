require 'sony_camera_remote_api'
require 'sony_camera_remote_api/scripts'
require 'sony_camera_remote_api/logging'
require 'sony_camera_remote_api/utils'
require 'sony_camera_remote_api/shelf'
require 'fileutils'
require 'thor'
require 'highline/import'


module SonyCameraRemoteAPI
  # CLI client module
  module Client

    # 'shelf' subcommand class for managing camera connection
    class ShelfCmd < Thor
      include Utils
      include Scripts

      class_option :file, aliases: '-f', type: :string, desc: 'Config file path', banner: 'FILE'

      no_tasks do
        def config_file
          options[:file] || GLOBAL_CONFIG_FILE
        end

        def read_or_create_shelf
          @shelf = Shelf.new config_file
        end

        def get_id_or_ssid(id_or_ssid)
          begin
            id = Integer(id_or_ssid)
            specified = @shelf.get_by_index id
            unless specified
              puts 'ERROR: Specified ID is invalid!'
              return
            end
          rescue ArgumentError
            ssid = id_or_ssid
            specified = @shelf.get(ssid)
            unless specified
              puts 'ERROR: Specified SSID is not found or too ambigous!'
              return
            end
          end
          specified
        end
      end


      desc 'add <SSID> <password> <interface>', 'Add a new camera connection'
      def add(ssid, pass, interface)
        read_or_create_shelf
        if @shelf.get_all.find { |c| c['ssid'] == ssid }
          # If SSID is duplicacted, ask user to overwrite or not.
          answer = $terminal.ask('SSID duplicated! Do you want to overwrite? ') { |q| q.validate = /[yn]/i; q.default = 'n' }
          if answer == 'y'
            @shelf.add ssid, pass, interface, overwrite: true
          else
            puts 'Entry not changed.'
            invoke :list, [], options
            return
          end
        else
          @shelf.add ssid, pass, interface
        end

        # Ask user to set default or not.
        if @shelf.get
          answer = $terminal.ask('Do you want set this camera as default? ') { |q| q.validate = /[yn]/i; q.default = 'y' }
          if answer == 'y'
            @shelf.select ssid
          end
        else
          @shelf.select ssid
        end

        invoke :list, [], options
      end


      desc 'list', 'List added cameras'
      def list
        read_or_create_shelf
        cameras = @shelf.get_all
        default = @shelf.get

        # No camera has been added, exit with a message.
        if cameras.empty?
          puts 'No camera yet!'
          puts "Use 'sonycam shelf add' to add a new camera config."
          return
        end

        # If default camera is not set, show message.
        if default
          default_ssid = default['ssid']
        else
          puts 'Default camera is not selected yet!'
          puts "Use 'sonycam shelf use' command to select camera to use as default."
          default_ssid = nil
        end

        # Selected camera is signed by allow
        cameras.each_with_index do |v, i|
          if v['ssid'] == default_ssid
            puts "=> #{i}: SSID      : #{v['ssid']} "
          else
            puts "   #{i}: SSID      : #{v['ssid']} "
          end
          puts "      Password  : #{v['pass']} "
          puts "      Interface : #{v['interface']} "
        end
      end


      desc 'remove <ID or SSID> [options]', 'Remove camera(s) from the shelf'
      option :all, type: :boolean, desc: 'Remove all cameras'
      def remove(id_or_ssid = nil)
        read_or_create_shelf
        if options[:all]
          @shelf.remove_all
          return
        end

        specified = get_id_or_ssid id_or_ssid
        @shelf.remove specified['ssid'] if specified

        invoke :list, [], options
      end


      desc 'select <ID or SSID>', 'Select a camera as default'
      def select(id_or_ssid)
        read_or_create_shelf

        specified = get_id_or_ssid id_or_ssid
        @shelf.select specified['ssid'] if specified

        invoke :list, [], options
      end


      desc 'interface <if-name> <ssid>', 'Set interface by which the camera is connected.'
      def interface(if_name, id_or_ssid = nil)
        read_or_create_shelf

        if id_or_ssid
          specified = get_id_or_ssid id_or_ssid
        else
          specified = @shelf.get
          unless specified
            puts 'ERROR: Default camera is not selected yet!'
            return
          end
        end
        @shelf.set_if if_name, specified['ssid'] if specified
        invoke :list, [], options
      end


      desc 'connect [options]', 'Connect to the default camera'
      option :restart, aliases: '-r', type: :boolean, desc: 'Restart interface', default: false
      option :ssid, aliases: '-s', type: :string, desc: 'Specify camera by SSID'
      def connect
        read_or_create_shelf

        if options[:ssid]
          camera = @shelf.get(options[:ssid])
          unless camera
            puts 'ERROR: Specified SSID is not found or too ambigous!'
            return
          end
        else
          camera = @shelf.get
          unless camera
            puts 'ERROR: Default camera is not selected yet!'
            return
          end
        end

        puts 'Camera to connect:'
        puts "  - SSID     : #{camera['ssid']}"
        puts "  - pass     : #{camera['pass']}"
        puts "  - inteface : #{camera['interface']}"

        # Connect to camera by external script
        if options[:restart]
          result = @shelf.reconnect camera['ssid']
        else
          result = @shelf.connect camera['ssid']
        end
        unless result
          puts 'Failed to connect!'
          exit 1
        end
      end
    end
  end
end
