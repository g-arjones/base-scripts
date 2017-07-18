require 'orogen'
require 'utilrb/module/attr_predicate'

module Rock
    class SearchItem
        attr_reader :object
        attr_accessor :project_name
        attr_reader :name
        def initialize(*info)
            if info.size != 1
                raise 'Wrong number of arguments'
            end
            info = info[0]
            @object = info[:object]
            @project_name = info[:project_name]
            @name = info[:name]
        end

        def eql?(obj)
            self == obj 
            name == obj.name
        end

        def hash
            name.hash
        end

        def ==(obj)
            name == obj.name
        end
    end

    class Inspect
        class << self
            attr_accessor :debug
            attr_predicate :has_vizkit?, true
        end

        Inspect.debug = false
        Inspect.has_vizkit = true

        def self.orogen_loader
            if !@orogen_loader
                loader = OroGen::Loaders::PkgConfig.new(OroGen.orocos_target)
                OroGen::Loaders::RTT.setup_loader(loader)
                @orogen_loader = loader
            end
            @orogen_loader
        end

        def self.load_orogen_typekit(loader, name, debug)
            begin
                loader.typekit_model_from_name(name)
            rescue Interrupt; raise
            rescue Exception => e
                if Rock::Inspect::debug
                    raise
                end
                OroGen.warn "cannot load the installed oroGen typekit #{name}"
                OroGen.warn "     #{e.message}"
                nil
            end
        end

        def self.load_orogen_project(loader, name, debug)
            begin
                loader.project_model_from_name(name)
            rescue Interrupt; raise
            rescue Exception => e
                if Rock::Inspect::debug
                    raise
                end
                OroGen.warn "cannot load the installed oroGen project #{name}"
                OroGen.warn "     #{e.message}"
                nil
            end
        end

        def self.find(pattern,filter = Hash.new)
            options, filter = Kernel::filter_options(filter,[:no_types,:no_ports,:no_tasks,:no_deployments,:no_projects,:no_plugins,:no_plugins,:no_widgets])
            result = Array.new

            #search for types
            #we are not searching for types all the time 
            if !options[:no_types]
                reg = filter.has_key?(:types) ? filter[:types] : pattern
                reg = /./ unless reg
                result += Rock::Inspect::find_types(/#{reg}/,filter)
            end

            #search for ports
            if !options[:no_ports]
                reg = filter.has_key?(:ports) ? filter[:ports] : pattern
                reg = /./ unless reg
                result += Rock::Inspect::find_ports(/#{reg}/,filter)
            end

            #search for tasks
            if !options[:no_tasks]
                reg = (filter[:tasks] || pattern || /./)
                result += Rock::Inspect::find_tasks(/#{reg}/, filter)
            end

            #search for deployments
            if !options[:no_deployments]
                reg = filter.has_key?(:deployments) ? filter[:deployments] : pattern
                reg = /./ unless reg
                result += Rock::Inspect::find_deployments(/#{reg}/,filter)
            end

            #search for plugins
            if !options[:no_plugins]
                reg = filter.has_key?(:plugins) ? filter[:plugins] : pattern
                reg = /./ unless reg
                result += Rock::Inspect::find_plugins(/#{reg}/, filter)
            end

            # Search for projects that have no tasks, but only deployments defined
            # Last entry before producing the result, to allow operation on the 
            # already contrained project list
            if !options[:no_projects]
                reg = filter.has_key?(:projects) ? filter[:projects] : pattern
                reg = /./ unless reg
                result += Rock::Inspect::find_projects(/#{reg}/,filter)
            end

            result.uniq.sort_by(&:name)
        end

        def self.find_tasks(pattern,filter = Hash.new)
            found = []
            filter,unkown = Kernel::filter_options(filter,[:types,:ports,:tasks])
            return found if !unkown.empty?

            #find all tasks which are matching the pattern
            orogen_loader.each_available_task_model_name do |name, project_name|
                if name =~ pattern || project_name =~ pattern
                    if tasklib = load_orogen_project(orogen_loader, project_name, Rock::Inspect::debug)
                        task = tasklib.self_tasks.values.find { |t| t.name == name }
                        if(task_match?(task,pattern,filter))
                            found << SearchItem.new(:name => "TaskContext::#{task.name}",
                                                    :project_name => project_name,
                                                        :object => task)
                        end
                    end
                end
            end
            found.sort_by{|t|t.name}
        end

        def self.find_ports(pattern,filter = Hash.new)
            found = []
            filter,unkown = Kernel::filter_options(filter,[:types,:ports])
            return found if !unkown.empty?
            #find all tasks which are matching the pattern
            orogen_loader.each_available_task_model_name.each do |name, project_name|
                if tasklib = load_orogen_project(orogen_loader, project_name, Rock::Inspect::debug)
                    tasklib.self_tasks.each_value do |task|
                        task.each_port do |port|
                            if(port_match?(port,pattern,filter))
                                found <<  SearchItem.new(:name => "Port::#{port.name}",
                                                         :project_name => project_name,
                                                             :object => port)
                                                         break
                            end
                        end
                    end
                end
            end
            found.sort_by{|t|t.name}
        end

        def self.find_types(pattern,filter = Hash.new)
            found = Array.new
            filter,unkown = Kernel::filter_options(filter,[:types])
            return found if !unkown.empty?
            orogen_loader.each_available_type_name do |type_name, typekit_name, exported|
                if pattern === type_name
                    orogen_loader.typekit_model_from_name(typekit_name)
                    object = orogen_loader.resolve_type(type_name)
                    if type_match?(object,pattern,filter)
                        found << SearchItem.new(:name => "Type::#{type_name}",
                                                :project_name => typekit_name,
                                                :object => object)
                    end
                end
            end
            found.sort_by{|t|t.name}
        end

        def self.find_deployments(pattern,filter=Hash.new)
            found = []
            filter,unkown = Kernel::filter_options(filter,[:types,:ports,:tasks,:deployments])
            return found if !unkown.empty?
            orogen_loader.each_available_project_name do |project_name|
                project = load_orogen_project(orogen_loader, project_name, Rock::Inspect::debug)
                project.deployers.values.each do |deployer|
                    if pattern === deployer.name || pattern === project.name ||
                        deployer.task_activities.find { |t| pattern === t.name || pattern === t.task_model.name }
                        found << SearchItem.new(:name => "Deployment::#{deployer.name}",
                                                :project_name => project_name,
                                                :object => deployer)

                    end
                end
            end
            found.sort_by{|t|t.name}
        end

        def self.find_projects(pattern, filter=Hash.new)
            found = []
            filter,unknown = Kernel::filter_options(filter,[:types,:ports,:tasks,:deployments,:projects])
            return found if !unknown.empty?

            # Check whether there have been already search filters set, 
            # meaning that the resulting project list should be a subset of those
            use_whitelist = false
            if !(filter.has_key?(:projects) && filter.size == 1)
                use_whitelist = true
            end
          
            # Either use all available projects or subset, as defined by the previous contrains 
            if use_whitelist 
                projects = found.map(&:name)
            else
                projects = orogen_loader.each_available_project_name.to_a
            end

            projects.each do |name|
                if project_match?(name,pattern,filter)
                    if tasklib = load_orogen_project(orogen_loader, name, Rock::Inspect::debug)
                        tasklib.deployers.each do |deployment|
                                found << SearchItem.new(:name => "Deployment::#{deployment.name}",
                                                        :project_name => name,
                                                        :object => deployment)
                        end
                    end
                end
            end
            found.sort_by{|t|t.name}
        end

        def self.find_plugins(pattern,filter=Hash.new)
            found = []
            filter,unkown = Kernel::filter_options(filter,[:plugin_name,:types])
            return found if !unkown.empty?
            specs = Vizkit.default_loader.plugin_specs
            specs.each_value do |spec|
                next if filter.has_key?(:plugin_name) && nil == (spec.plugin_name =~ filter[:plugin_name])
                if((spec2 = spec.callback_specs.find(){|callback|callback.argument =~ pattern}) || spec.plugin_name =~ pattern)
                    next if filter.has_key?(:types) && (!spec2 ||nil == (spec2.argument =~ filter[:types]))
                    found << SearchItem.new(:name => spec.plugin_name, :object => spec)
                end
            end
            found.sort_by{|t|t.name}
        end

        def self.deployment_match?(deployment,pattern,filter = Hash.new)
            return false if (!(deployment.name =~ pattern))
            return false if (filter.has_key?(:deployments) && !(deployment.name =~ filter[:deployments]))
            return false if (deployment.task_activities.all?{|t| !( task_match?(t.task_model,//,filter))})
            true
        end

        def self.project_match?(project_name,pattern,filter = Hash.new)
            return true if (project_name =~ pattern)
            return true if (filter.has_key?(:projects) && (project_name =~ filter[:projects]))
            false
        end

        def self.type_match?(type,pattern,filter = Hash.new)
            true
        end

        def self.port_match?(port,pattern,filter = Hash.new)
            return false if (!(port.name =~ pattern) && !(port.type_name =~ pattern))
            return false if (filter.has_key?(:tasks) && !(port.task.name =~ filter[:tasks]))
            return false if (filter.has_key?(:ports) && !(port.name =~ filter[:ports]))
            return false if (filter.has_key?(:types) && !(port.type_name =~ filter[:types]))
            true
        end

        def self.task_match?(task,pattern,filter= Hash.new)
            return false unless task.name =~ pattern
            return false if(filter.has_key?(:tasks) && !(task.name =~ filter[:tasks]))
            has_port = false
            #we have to disable the filter :task otherwise there will be trouble with subclasses
            old = filter.delete :tasks
            task.each_port {|port| has_port = true if(port_match?(port,//,filter))}
            return false if !has_port
            filter[:tasks] = old if old
            if filter.has_key? :types
                has_type= false
                task.each_port {|port| has_type = true if(port.type_name =~ filter[:types])}
                task.each_property {|property| has_type = true if(property.type_name.to_s =~ filter[:types])}
                task.each_attribute {|attribute| has_type = true if(attribute.type_name.to_s =~ filter[:types])}
                return false if !has_type
            end
            #return false if(filter.has_key?(:deployments) && !(task.name =~ filter[:tasks]))
            true
        end
    end

    class GenericView
        attr_reader :name

        def initialize(search_item)
            obj = search_item.object
            @name = search_item.name
            @project_name = search_item.project_name
            @object = obj
            @header = "Name:"
            @header2 = nil
        end

        def hash
            @name.hash
        end

        def eql?(obj)
            self == obj
        end

        def ==(obj)
            @name == obj.name
        end

        def pretty_print(pp)
            pp.text "=========================================================="
            pp.breakable
            pp.text "#{@header} #{@name}"
            pp.breakable
            pp.text "defined in #{@project_name}"
            pp.breakable
            if @header2
                pp.text "#{@header2}"
                pp.breakable
            end
            pp.text "----------------------------------------------------------"
            if((@object && @object.respond_to?(:pretty_print)))
                pp.breakable
                pp.nest(2) do 
                    pp.breakable
                    @object.pretty_print(pp)
                end
            end
            pp.breakable
        end
    end

    class WidgetView < GenericView
        def initialize(search_item)
            super
        end

        def pretty_print(pp)
            pp @object 
        end
    end

    class DeploymentView < GenericView
        def initialize(search_item)
            super
            @header = "Deployment name: "
	    @name = @name.gsub(/^\w+::/, '')
        end
    end

    class TypeView < GenericView
        def initialize(search_item)
            super
            @header = "Typelib name: "
	    @name = @name.gsub(/^\w+::/, '')
        end
    end

    class PortView < GenericView
        def initialize(search_item)
            super
            @header = "Port name: "
            @header2 = "defined in Task #{search_item.object.task.name}"
        end
    end

    class TaskView < GenericView
        attr_reader :name
        def initialize(search_item)
            obj = search_item.object
            obj = obj.task if obj.is_a? OroGen::Spec::Port

            @name = obj.name
            @project_name = search_item.project_name
            @object = obj
            @header = "Task name: "
        end
    end
end


begin
    if ENV['DISPLAY']
        require 'vizkit'
    else
        Rock::Inspect.has_vizkit = false
    end
rescue LoadError
    Rock::Inspect.has_vizkit = false
end

