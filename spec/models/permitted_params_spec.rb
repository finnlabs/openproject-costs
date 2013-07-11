require File.expand_path('../../spec_helper', __FILE__)

describe PermittedParams do
  let(:user) { FactoryGirl.build(:user) }

  describe :cost_entry do
    it "should return comments" do
      params = ActionController::Parameters.new(:cost_entry => { "comments" => "blubs" } )

      PermittedParams.new(params, user).cost_entry.should == { "comments" => "blubs" }
    end

    it "should return units" do
      params = ActionController::Parameters.new(:cost_entry => { "units" => "5.0" } )

      PermittedParams.new(params, user).cost_entry.should == { "units" => "5.0" }
    end

    it "should return overridden_costs" do
      params = ActionController::Parameters.new(:cost_entry => { "overridden_costs" => "5.0" } )

      PermittedParams.new(params, user).cost_entry.should == { "overridden_costs" => "5.0" }
    end

    it "should return spent_on" do
      params = ActionController::Parameters.new(:cost_entry => { "spent_on" => Date.today.to_s } )

      PermittedParams.new(params, user).cost_entry.should == { "spent_on" => Date.today.to_s }
    end

    it "should not return project_id" do
      params = ActionController::Parameters.new(:cost_entry => { "project_id" => 42 } )

      PermittedParams.new(params, user).cost_entry.should == { }
    end
  end

  describe :cost_object do
    it "should return comments" do
      params = ActionController::Parameters.new(:cost_object => { "subject" => "subject_test" } )

      PermittedParams.new(params, user).cost_object.should == { "subject" => "subject_test" }
    end

    it "should return description" do
      params = ActionController::Parameters.new(:cost_object => { "description" => "description_test" } )

      PermittedParams.new(params, user).cost_object.should == { "description" => "description_test" }
    end

    it "should return fixed_date" do
      params = ActionController::Parameters.new(:cost_object => { "fixed_date" => "2013-05-06" } )

      PermittedParams.new(params, user).cost_object.should == { "fixed_date" => "2013-05-06" }
    end

    it "should not return project_id" do
      params = ActionController::Parameters.new(:cost_object => { "project_id" => 42 } )

      PermittedParams.new(params, user).cost_object.should == { }
    end
  end

  describe :cost_type do
    it "should return name" do
      params = ActionController::Parameters.new(:cost_type => { "name" => "name_test" } )

      PermittedParams.new(params, user).cost_type.should == { "name" => "name_test" }
    end

    it "should return unit" do
      params = ActionController::Parameters.new(:cost_type => { "unit" => "unit_test" } )

      PermittedParams.new(params, user).cost_type.should == { "unit" => "unit_test" }
    end

    it "should return unit_plural" do
      params = ActionController::Parameters.new(:cost_type => { "unit_plural" => "unit_plural_test" } )

      PermittedParams.new(params, user).cost_type.should == { "unit_plural" => "unit_plural_test" }
    end

    it "should return default" do
      params = ActionController::Parameters.new(:cost_type => { "default" => 7 } )

      PermittedParams.new(params, user).cost_type.should == { "default" => 7 }
    end

    it "should return new_rate_attributes" do
      params = ActionController::Parameters.new(:cost_type => { "new_rate_attributes" => { "0" => { "valid_from" => "2013-05-08", "rate" => "5002" }, "1" => { "valid_from" => "2013-05-10", "rate" => "5004" } } } )

      PermittedParams.new(params, user).cost_type.should == { "new_rate_attributes" => { "0" => { "valid_from" => "2013-05-08", "rate" => "5002" }, "1" => { "valid_from" => "2013-05-10", "rate" => "5004" } } }
    end

    it "should return existing_rate_attributes" do
      params = ActionController::Parameters.new(:cost_type => { "existing_rate_attributes" => { "9" => { "valid_from" => "2013-05-05", "rate" => "50.0" } } } )

      PermittedParams.new(params, user).cost_type.should == { "existing_rate_attributes" => { "9" => { "valid_from" => "2013-05-05", "rate" => "50.0" } } }
    end

    it "should not return project_id" do
      params = ActionController::Parameters.new(:cost_type => { "project_id" => 42 } )

      PermittedParams.new(params, user).cost_type.should == { }
    end
  end

  describe :user_rates do
    it "should return new_rate_attributes" do
      params = ActionController::Parameters.new(:user => { "new_rate_attributes" => { "0" => { "valid_from" => "2013-05-08", "rate" => "5002" },
                                                                                      "1" => { "valid_from" => "2013-05-10", "rate" => "5004" } } } )

      PermittedParams.new(params, user).user_rates.should == { "new_rate_attributes" => { "0" => { "valid_from" => "2013-05-08", "rate" => "5002" },
                                                                                         "1" => { "valid_from" => "2013-05-10", "rate" => "5004" } } }
    end

    it "should return existing_rate_attributes" do
      params = ActionController::Parameters.new(:user => { "existing_rate_attributes" => { "0" => { "valid_from" => "2013-05-08", "rate" => "5002" },
                                                                                           "1" => { "valid_from" => "2013-05-10", "rate" => "5004" } } } )

      PermittedParams.new(params, user).user_rates.should == { "existing_rate_attributes" => { "0" => { "valid_from" => "2013-05-08", "rate" => "5002" },
                                                                                              "1" => { "valid_from" => "2013-05-10", "rate" => "5004" } } }
    end

  end

  describe :new_work_package do
    it "should permit cost_object_id" do
      hash = { "cost_object_id" => "1" }

      params = ActionController::Parameters.new(:work_package => hash)

      PermittedParams.new(params, user).new_work_package.should == hash
    end
  end
end
