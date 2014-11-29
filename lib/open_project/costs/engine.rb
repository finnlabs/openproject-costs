#-- copyright
# OpenProject Costs Plugin
#
# Copyright (C) 2009 - 2014 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#++

require 'open_project/plugins'

module OpenProject::Costs
  class Engine < ::Rails::Engine
    engine_name :openproject_costs

    include OpenProject::Plugins::ActsAsOpEngine

    register 'openproject-costs',
             author_url: 'http://finn.de',
             requires_openproject: '>= 4.0.0',
             settings:  { default: { 'costs_currency' => 'EUR', 'costs_currency_format' => '%n %u' },
                          partial: 'settings/openproject_costs' } do

      project_module :costs_module do
        permission :view_own_hourly_rate, {}
        permission :view_hourly_rates, {}

        permission :edit_own_hourly_rate, { hourly_rates: [:set_rate, :edit, :update] },
                   require: :member
        permission :edit_hourly_rates, { hourly_rates: [:set_rate, :edit, :update] },
                   require: :member
        permission :view_cost_rates, {} # cost item values

        permission :log_own_costs, { costlog: [:new, :create] },
                   require: :loggedin
        permission :log_costs, { costlog: [:new, :create] },
                   require: :member

        permission :edit_own_cost_entries, { costlog: [:edit, :update, :destroy] },
                   require: :loggedin
        permission :edit_cost_entries, { costlog: [:edit, :update, :destroy] },
                   require: :member

        permission :view_cost_objects, cost_objects: [:index, :show]

        permission :view_cost_entries,  cost_objects: [:index, :show], costlog: [:index]
        permission :view_own_cost_entries,  cost_objects: [:index, :show], costlog: [:index]

        permission :edit_cost_objects, cost_objects: [:index, :show, :edit, :update, :destroy, :new, :create, :copy]
      end

      # register additional permissions for the time log
      project_module :time_tracking do
        permission :view_own_time_entries, timelog: [:index, :report]
      end

      # Menu extensions
      menu :top_menu,
           :cost_types,
           { controller: '/cost_types', action: 'index' },
           caption: :cost_types_title,
           if: Proc.new { User.current.admin? }

      menu :project_menu,
           :cost_objects,
           { controller: '/cost_objects', action: 'index' },
           param: :project_id,
           before: :settings,
           caption: :cost_objects_title,
           html: { class: 'icon2 icon-budget' }

      menu :project_menu,
           :new_budget,
           { controller: '/cost_objects', action: 'new' },
           param: :project_id,
           caption: :label_cost_object_new,
           parent: :cost_objects,
           html: { class: 'icon2 icon-add' }

      menu :project_menu,
           :show_all,
           { controller: '/cost_objects', action: 'index' },
           param: :project_id,
           caption: :label_view_all_cost_objects,
           parent: :cost_objects,
           html: { class: 'icon2 icon-list-view1' }

      Redmine::Activity.map do |activity|
        activity.register :cost_objects, class_name: 'Activity::CostObjectActivityProvider', default: false
      end
    end

    patches [:WorkPackage, :Project, :Query, :User, :TimeEntry, :PermittedParams,
             :ProjectsController, :ApplicationHelper, :UsersHelper]

    extend_api_response(:v3, :work_packages, :work_package) do
      include Redmine::I18n
      include ActionView::Helpers::NumberHelper

      link :log_costs do
        {
          href: new_work_packages_cost_entry_path(represented),
          type: 'text/html',
          title: "Log costs on #{represented.subject}"
        } if costs_enabled && current_user_allowed_to(:log_costs)
      end

      link :timeEntries do
        {
          href: work_package_time_entries_path(represented.id),
          type: 'text/html',
          title: 'Time entries'
        } if user_has_time_entry_permissions?
      end

      property :cost_object,
               embedded: true,
               exec_context: :decorator,
               class: ::CostObject,
               decorator: ::API::V3::CostObjects::CostObjectRepresenter,
               if: -> (*) { costs_enabled && !represented.cost_object.nil? }

      property :overall_costs,
               exec_context: :decorator,
               if: -> (*) { costs_enabled }

      property :summarized_cost_entries,
               embedded: true,
               exec_context: :decorator,
               if: -> (*) { costs_enabled && current_user_allowed_to_view_summarized_cost_entries }

      property :spent_time,
               getter: -> (*) { Duration.new(hours: represented.spent_hours).iso8601 },
               writeable: false,
               exec_context: :decorator,
               if: -> (_) { user_has_time_entry_permissions? }

      send(:define_method, :current_user_allowed_to_view_summarized_cost_entries) do
        current_user_allowed_to(:view_cost_entries) ||
          current_user_allowed_to(:view_own_cost_entries)
      end

      send(:define_method, :overall_costs) do
        number_to_currency(attributes_helper.overall_costs)
      end

      send(:define_method, :summarized_cost_entries) do
        attributes_helper.summarized_cost_entries
          .map do |c|
          ::API::V3::CostTypes::CostTypeRepresenter
            .new(c[0],
                 c[1],
                 work_package: represented,
                 current_user: @current_user)
        end
      end

      send(:define_method, :attributes_helper) do
        @attributes_helper ||= OpenProject::Costs::AttributesHelper.new(represented)
      end

      send(:define_method, :costs_enabled) do
        represented.project && represented.project.module_enabled?(:costs_module)
      end

      send(:define_method, :cost_object) do
        represented.cost_object
      end

      send(:define_method, :user_has_time_entry_permissions?) do
        current_user_allowed_to(:view_time_entries) ||
          (current_user_allowed_to(:view_own_time_entries) && costs_enabled)
      end
    end

    assets %w(costs/costs.css
              costs/costs.js
              work_packages/cost_object.html
              work_packages/summarized_cost_entries.html)

    initializer 'costs.register_hooks' do
      require 'open_project/costs/hooks'
      require 'open_project/costs/hooks/activity_hook'
      require 'open_project/costs/hooks/work_package_hook'
      require 'open_project/costs/hooks/project_hook'
      require 'open_project/costs/hooks/work_package_action_menu'
      require 'open_project/costs/hooks/work_packages_show_attributes'
    end

    initializer 'costs.register_observers' do |_app|
      # Observers
      ActiveRecord::Base.observers.push :rate_observer, :default_hourly_rate_observer, :costs_work_package_observer
    end

    initializer 'costs.register_test_path' do |app|
      require File.join(File.dirname(__FILE__), 'disabled_specs')
      app.config.plugins_to_test_paths << root
    end

    initializer 'costs.patch_number_helper' do |_app|
      # we have to do the patching in the initializer to make sure we only do this once in development
      # since the NumberHelper is not unloaded
      ActionView::Helpers::NumberHelper.send(:include, OpenProject::Costs::Patches::NumberHelperPatch)
    end

    config.to_prepare do
      # loading the class so that acts_as_journalized gets registered
      VariableCostObject

      # TODO: this recreates the original behaviour
      # however, it might not be desirable to allow assigning of cost_object regardless of the permissions
      PermittedParams.permit(:new_work_package, :cost_object_id)
    end

    config.to_prepare do |_app|
      NonStupidDigestAssets.whitelist << /work_packages\/.*\.html/
    end
  end
end
