class CostlogController < ApplicationController
  unloadable

  menu_item :issues
  before_filter :find_project, :authorize, :only => [:edit,
                                                     :new,
                                                     :create,
                                                     :update,
                                                     :destroy]
  before_filter :find_associated_objects, :only => [:create,
                                                    :update]
  before_filter :find_optional_project, :only => [:report,
                                                  :index]

  helper :sort
  include SortHelper
  helper :issues
  include CostlogHelper

  def index
    # this looks like it should be moved to openproject_reporting
    # as it redirects to the CostReportsController and uses CostQuery.
    # both are defined in openproject_reporting
    unless @project.nil?
      filters = {:operators => {}, :values => {}}

      if @issue
        if @issue.respond_to?("lft")
          issue_ids = Issue.all(:select => :id, :conditions => ["root_id = ? AND lft >= ? AND rgt <= ?", @issue.root_id, @issue.lft, @issue.rgt]).collect{|i| i.id}
        else
          issue_ids = [@issue.id]
        end

        filters[:operators][:issue_id] = "="
        filters[:values][:issue_id] = issue_ids
      end

      filters[:operators][:project_id] = "="
      filters[:values][:project_id] = [@project.id.to_s]

      respond_to do |format|
        format.html {
          session[CostQuery.name.underscore.to_sym] = { :filters => filters, :groups => {:rows => [], :columns => []} }

          if @cost_type
            redirect_to :controller => "/cost_reports", :action => "index", :project_id => @project, :unit => @cost_type.id
          else
            redirect_to :controller => "/cost_reports", :action => "index", :project_id => @project
          end
          return
        }
      end
    end

    sort_init 'spent_on', 'desc'
    sort_update 'spent_on' => 'spent_on',
                'user' => 'user_id',
                'project' => "#{Project.table_name}.name",
                'issue' => 'issue_id',
                'cost_type' => 'cost_type_id',
                'units' => 'units',
                'costs' => 'costs'

    cond = ARCondition.new
    if @project.nil?
      cond << Project.allowed_to_condition(User.current, :view_cost_entries)
    elsif @issue.nil?
      cond << @project.project_condition(Setting.display_subprojects_issues?)
    else
      cond << "#{Issue.table_name}.root_id = #{@issue.root_id} AND #{Issue.table_name}.lft >= #{@issue.lft} AND #{Issue.table_name}.rgt <= #{@issue.rgt}"
    end

    cond << User.current.allowed_for(:view_cost_entries, @project)

    if @cost_type
      cond << ["#{CostEntry.table_name}.cost_type_id = ?", @cost_type.id ]
    end

    retrieve_date_range
    cond << ['spent_on BETWEEN ? AND ?', @from, @to]

    CostEntry.visible_by(User.current) do
      respond_to do |format|
        format.html {
          # Paginate results
          @entry_count = CostEntry.count(:include => [:project, :user], :conditions => cond.conditions)
          @entry_pages = Paginator.new self, @entry_count, per_page_option, params['page']
          @entries = CostEntry.find(:all,
                                    :include => [:project, :cost_type, :user, {:issue => :tracker}],
                                    :conditions => cond.conditions,
                                    :order => sort_clause,
                                    :limit  =>  @entry_pages.items_per_page,
                                    :offset =>  @entry_pages.current.offset)

          render :layout => !request.xhr?
        }
        format.atom {
          entries = TimeEntry.find(:all,
                                   :include => [:project, :cost_type, :user, {:issue => :tracker}],
                                   :conditions => cond.conditions,
                                   :order => "#{CostEntry.table_name}.created_on DESC",
                                   :limit => Setting.feeds_limit.to_i)
          render_feed(entries, :title => l(:label_spent_costs))
        }
        format.csv {
          # Export all entries
          @entries = CostEntry.find(:all,
                                    :include => [:project, :cost_type, :user, {:issue => [:tracker, :assigned_to, :priority]}],
                                    :conditions => cond.conditions,
                                    :order => sort_clause)
          send_data(entries_to_csv(@entries).read, :type => 'text/csv; header=present', :filename => 'costlog.csv')
        }
      end
    end
  end

  def new
    new_default_cost_entry

    render :action => 'edit'
  end

  def edit
    render_403 unless @cost_entry.try(:editable_by?, User.current)
  end

  def create
    new_default_cost_entry
    update_cost_entry_from_params

    if !@cost_entry.creatable_by?(User.current)

      render_403

    elsif @cost_entry.save

      flash[:notice] = l(:notice_successful_create)
      redirect_back_or_default :action => 'index', :project_id => @cost_entry.project

    else
      render :action => 'edit'
    end
  end

  def update
    update_cost_entry_from_params

    if !@cost_entry.editable_by?(User.current)

      render_403

    elsif @cost_entry.save

      flash[:notice] = l(:notice_successful_update)
      redirect_back_or_default :action => 'index', :project_id => @cost_entry.project

    else
      render :action => 'edit'
    end
  end

  verify :method => :delete, :only => :destroy, :render => {:nothing => true, :status => :method_not_allowed }
  def destroy
    render_404 and return unless @cost_entry
    render_403 and return unless @cost_entry.editable_by?(User.current)
    @cost_entry.destroy
    flash[:notice] = l(:notice_successful_delete)

    if request.referer =~ /cost_reports/
      redirect_to :controller => '/cost_reports', :action => :index
    else
      redirect_to :back
    end
  rescue ::ActionController::RedirectBackError
    redirect_to :action => 'index', :project_id => @cost_entry.project
  end

  def get_cost_type_unit_plural
    @cost_type = CostType.find(params[:cost_type_id]) unless params[:cost_type_id].empty?

    if request.xhr?
      render :partial => "cost_type_unit_plural", :layout => false
    end
  end

private
  def find_project
    # copied from timelog_controller.rb
    if params[:id]
      @cost_entry = CostEntry.find(params[:id])
      @project = @cost_entry.project
    elsif params[:issue_id]
      @issue = Issue.find(params[:issue_id])
      @project = @issue.project
    elsif params[:project_id]
      @project = Project.find(params[:project_id])
    else
      render_404
      return false
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_optional_project
    if !params[:issue_id].blank?
      @issue = Issue.find(params[:issue_id])
      @project = @issue.project
    elsif !params[:project_id].blank?
      @project = Project.find(params[:project_id])
    end

    if !params[:cost_type_id].blank?
      @cost_type = CostType.find(params[:cost_type_id])
    end
  end

  def find_associated_objects
    user_id = params[:cost_entry].delete(:user_id)
    @user = @cost_entry.present? && @cost_entry.user_id == user_id ?
              @cost_entry.user :
              User.find_by_id(user_id)

    issue_id = params[:cost_entry].delete(:issue_id)
    @issue = @cost_entry.present? && @cost_entry.issue_id == issue_id ?
               @cost_entry.issue :
               Issue.find_by_id(issue_id)

    cost_type_id = params[:cost_entry].delete(:cost_type_id)
    @cost_type = @cost_entry.present? && @cost_entry.cost_type_id == cost_type_id ?
                   @cost_entry.cost_type :
                   CostType.find_by_id(cost_type_id)
  end

  def retrieve_date_range
    # Mostly copied from timelog_controller.rb
    @free_period = false
    @from, @to = nil, nil

    if params[:period_type] == '1' || (params[:period_type].nil? && !params[:period].nil?)
      case params[:period].to_s
      when 'today'
        @from = @to = Date.today
      when 'yesterday'
        @from = @to = Date.today - 1
      when 'current_week'
        @from = Date.today - (Date.today.cwday - 1)%7
        @to = @from + 6
      when 'last_week'
        @from = Date.today - 7 - (Date.today.cwday - 1)%7
        @to = @from + 6
      when '7_days'
        @from = Date.today - 7
        @to = Date.today
      when 'current_month'
        @from = Date.civil(Date.today.year, Date.today.month, 1)
        @to = (@from >> 1) - 1
      when 'last_month'
        @from = Date.civil(Date.today.year, Date.today.month, 1) << 1
        @to = (@from >> 1) - 1
      when '30_days'
        @from = Date.today - 30
        @to = Date.today
      when 'current_year'
        @from = Date.civil(Date.today.year, 1, 1)
        @to = Date.civil(Date.today.year, 12, 31)
      end
    elsif params[:period_type] == '2' || (params[:period_type].nil? && (!params[:from].nil? || !params[:to].nil?))
      begin; @from = params[:from].to_s.to_date unless params[:from].blank?; rescue; end
      begin; @to = params[:to].to_s.to_date unless params[:to].blank?; rescue; end
      @free_period = true
    else
      # default
    end

    @from, @to = @to, @from if @from && @to && @from > @to
    @from ||= (CostEntry.minimum(:spent_on, :include => [:project, :user], :conditions => User.current.allowed_for(:view_cost_entries)) || Date.today) - 1
    @to   ||= (CostEntry.maximum(:spent_on, :include => [:project, :user], :conditions => User.current.allowed_for(:view_cost_entries)) || Date.today)
  end

  def new_default_cost_entry
    @cost_entry = CostEntry.new.tap do |ce|
      ce.project  = @project
      ce.issue = @issue
      ce.user = User.current
      ce.spent_on = Date.today
      # notice that cost_type is set to default cost_type in the model
    end
  end

  def update_cost_entry_from_params
    @cost_entry.user = @user
    @cost_entry.issue = @issue
    @cost_entry.cost_type = @cost_type

    @cost_entry.attributes = permitted_params.cost_entry
  end
end
