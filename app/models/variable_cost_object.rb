class VariableCostObject < CostObject
  unloadable

  has_many :material_budget_items, :include => :cost_type,
                                   :foreign_key => 'cost_object_id',
                                   :dependent => :destroy
  has_many :labor_budget_items, :include => :user,
                                :foreign_key => 'cost_object_id',
                                :dependent => :destroy

  validates_associated :material_budget_items
  validates_associated :labor_budget_items

  after_update :save_material_budget_items
  after_update :save_labor_budget_items

  if respond_to? :acts_as_journalized
    acts_as_journalized :event_type => 'cost-object',
                        :event_title => Proc.new {|o| "#{l(:label_cost_object)} ##{o.journaled.id}: #{o.subject}"},
                        :event_url => Proc.new {|o| {:controller => 'cost_objects', :action => 'show', :id => o.journaled.id}},
                        :activity_type => superclass.plural_name,
                        :activity_find_options => {:include => [:project, :author]},
                        :activity_timestamp => "#{table_name}.updated_on",
                        :activity_author_key => :author_id,
                        :activity_permission => :view_cost_objects

  end

  # override acts_as_journalized method
  def activity_type
    self.class.superclass.plural_name
  end

  def copy_from(arg)
    cost_object = (arg.is_a?(VariableCostObject) ? arg : self.class.find(arg))
    attrs = cost_object.attributes.dup
    super(attrs)
    self.labor_budget_items = cost_object.labor_budget_items.collect(&:dup)
    self.material_budget_items = cost_object.material_budget_items.collect(&:dup)
  end

  # Label of the current cost_object type for display in GUI.
  def type_label
    return l(:label_variable_cost_object)
  end

  def material_budget
    @material_budget ||= material_budget_items.visible_costs.inject(BigDecimal.new("0.0000")){|sum, i| sum += i.costs}
  end

  def labor_budget
    @labor_budget ||= labor_budget_items.visible_costs.inject(BigDecimal.new("0.0000")){|sum, i| sum += i.costs}
  end

  def spent
    spent_material + spent_labor
  end

  def spent_material
    @spent_material ||= begin
      if cost_entries.blank?
        BigDecimal.new("0.0000")
      else
        cost_entries.visible_costs(User.current, self.project).sum("CASE
          WHEN #{CostEntry.table_name}.overridden_costs IS NULL THEN
            #{CostEntry.table_name}.costs
          ELSE
            #{CostEntry.table_name}.overridden_costs END").to_d
      end
    end
  end

  def spent_labor
    @spent_labor ||= begin
      if time_entries.blank?
        BigDecimal.new("0.0000")
      else
        time_entries.visible_costs(User.current, self.project).sum("CASE
          WHEN #{TimeEntry.table_name}.overridden_costs IS NULL THEN
            #{TimeEntry.table_name}.costs
          ELSE
            #{TimeEntry.table_name}.overridden_costs END").to_d
      end
    end
  end

  def new_material_budget_item_attributes=(material_budget_item_attributes)
    material_budget_item_attributes.each do |index, attributes|
      material_budget_items.build(attributes) if attributes[:units].to_i > 0
    end
  end

  def existing_material_budget_item_attributes=(material_budget_item_attributes)
    material_budget_items.reject(&:new_record?).each do |material_budget_item|
      attributes = material_budget_item_attributes[material_budget_item.id.to_s]

      if User.current.allowed_to? :edit_cost_objects, material_budget_item.cost_object.project
        if attributes && attributes[:units].to_i > 0
          attributes[:budget] = Rate.clean_currency(attributes[:budget])
          material_budget_item.attributes = attributes
        else
          material_budget_items.delete(material_budget_item)
        end
      end
    end
  end

  def save_material_budget_items
    material_budget_items.each do |material_budget_item|
      material_budget_item.save(:validate => false)
    end
  end

  def new_labor_budget_item_attributes=(labor_budget_item_attributes)
    labor_budget_item_attributes.each do |index, attributes|
      if attributes[:hours].to_i > 0 &&
         attributes[:user_id].to_i > 0 &&
         project.assignable_users.map(&:id).include?(attributes[:user_id].to_i)

        item = labor_budget_items.build(attributes)
        item.cost_object = self # to please the labor_budget_item validation
      end
    end
  end

  def existing_labor_budget_item_attributes=(labor_budget_item_attributes)
    labor_budget_items.reject(&:new_record?).each do |labor_budget_item|
      attributes = labor_budget_item_attributes[labor_budget_item.id.to_s]
      if User.current.allowed_to? :edit_cost_objects, labor_budget_item.cost_object.project
        if attributes && attributes[:hours].to_i > 0 && attributes[:user_id].to_i > 0 && project.assignable_users.map(&:id).include?(attributes[:user_id].to_i)
          attributes[:budget] = Rate.clean_currency(attributes[:budget])
          labor_budget_item.attributes = attributes
        else
          labor_budget_items.delete(labor_budget_item)
        end
      end
    end
  end

  def save_labor_budget_items
    labor_budget_items.each do |labor_budget_item|
      labor_budget_item.save(:validate =>false)
    end
  end
end
