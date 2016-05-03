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

require 'spec_helper'

describe ::API::V3::WorkPackages::WorkPackageRepresenter do
  include API::V3::Utilities::PathHelper

  let(:project) { FactoryGirl.create(:project) }
  let(:role) {
    FactoryGirl.create(:role, permissions: [:view_time_entries,
                                            :view_cost_entries,
                                            :view_cost_rates,
                                            :view_work_packages])
  }
  let(:own_time_entries_role) {
    FactoryGirl.create(:role, permissions: [:view_time_entries,
                                            :view_cost_entries,
                                            :view_cost_rates,
                                            :view_work_packages])
  }
  let(:user) {
    FactoryGirl.create(:user,
                       member_in_project: project,
                       member_through_role: role)
  }

  let(:cost_object) { FactoryGirl.create(:cost_object, project: project) }
  let(:cost_entry_1) {
    FactoryGirl.create(:cost_entry,
                       work_package: work_package,
                       project: project,
                       units: 3,
                       spent_on: Date.today,
                       user: user,
                       comments: 'Entry 1')
  }
  let(:cost_entry_2) {
    FactoryGirl.create(:cost_entry,
                       work_package: work_package,
                       project: project,
                       units: 3,
                       spent_on: Date.today,
                       user: user,
                       comments: 'Entry 2')
  }

  let(:work_package) {
    FactoryGirl.create(:work_package,
                       project_id: project.id,
                       cost_object: cost_object)
  }
  let(:representer) {
    described_class.new(work_package,
                        current_user: user,
                        embed_links: true)
  }

  before(:each) do
    allow(User).to receive(:current).and_return user
  end

  subject(:generated) { representer.to_json }

  describe 'generation' do
    before do
      cost_entry_1
      cost_entry_2
    end

    describe 'work_package' do
      # specifiying as it used to be different
      it { is_expected.to have_json_path('spentTime') }

      it { is_expected.not_to have_json_path('spentHours') }

      it { is_expected.to have_json_path('overallCosts') }

      describe 'budget' do
        it_behaves_like 'has a titled link' do
          let(:link) { 'costObject' }
          let(:href) { "/api/v3/budgets/#{cost_object.id}" }
          let(:title) { cost_object.subject }
        end

        it 'has the budget embedded' do
          is_expected.to be_json_eql(cost_object.subject.to_json)
            .at_path('_embedded/costObject/subject')
        end
      end

      it_behaves_like 'has an untitled link' do
        let(:link) { 'costsByType' }
        let(:href) { api_v3_paths.summarized_work_package_costs_by_type work_package.id }
      end

      it 'embeds the costsByType' do
        is_expected.to have_json_path('_embedded/costsByType')
      end

      describe 'spentTime' do
        context 'time entry with single hour' do
          let(:time_entry) {
            FactoryGirl.create(:time_entry,
                               project: work_package.project,
                               work_package: work_package,
                               hours: 1.0)
          }

          before do time_entry end

          it { is_expected.to be_json_eql('PT1H'.to_json).at_path('spentTime') }
        end

        context 'time entry with multiple hours' do
          let(:time_entry) {
            FactoryGirl.create(:time_entry,
                               project: work_package.project,
                               work_package: work_package,
                               hours: 42.5)
          }

          before do time_entry end

          it { is_expected.to be_json_eql('P1DT18H30M'.to_json).at_path('spentTime') }
        end

        context 'no view_time_entries permission' do
          before do
            allow(user).to receive(:allowed_to?).and_return false
          end

          it { is_expected.not_to have_json_path('spentTime') }
        end

        context 'only view_own_time_entries permission' do
          let(:own_time_entries_role) {
            FactoryGirl.create(:role, permissions: [:view_own_time_entries,
                                                    :view_work_packages])
          }

          let(:user2) {
            FactoryGirl.create(:user,
                               member_in_project: project,
                               member_through_role: own_time_entries_role)
          }

          let!(:own_time_entry) {
            FactoryGirl.create(:time_entry,
                               project: work_package.project,
                               work_package: work_package,
                               hours: 2,
                               user: user2)
          }

          let!(:other_time_entry) {
            FactoryGirl.create(:time_entry,
                               project: work_package.project,
                               work_package: work_package,
                               hours: 1,
                               user: user)
          }

          before do
            allow(User).to receive(:current).and_return(user2)
          end

          it { is_expected.to be_json_eql('PT2H'.to_json).at_path('spentTime') }
        end

        context 'no time entry' do
          it { is_expected.to be_json_eql('PT0S'.to_json).at_path('spentTime') }
        end
      end
    end
  end

  describe '_links' do
    describe 'move' do
      it_behaves_like 'action link' do
        let(:action) { 'log_costs' }
        let(:permission) { :log_costs }
      end
    end

    describe 'timeEntries' do
      it 'exists if user has view_time_entries permission' do
        allow(user).to receive(:allowed_to?).and_return false
        allow(user).to receive(:allowed_to?).with(:view_time_entries,
                                                  cost_object.project)
          .and_return true

        is_expected.to have_json_path('_links/timeEntries/href')
      end

      it 'has spentTime link when user only has view_own_time_entries permission' do
        allow(user).to receive(:allowed_to?).and_return false
        allow(user).to receive(:allowed_to?).with(:view_own_time_entries,
                                                  cost_object.project)
          .and_return true

        is_expected.to have_json_path('_links/timeEntries/href')
      end
    end
  end

  describe 'costs module disabled' do
    before do
      allow(work_package).to receive(:costs_enabled?).and_return false
    end

    describe 'work_package' do
      it { is_expected.to have_json_path('spentTime') }

      it { is_expected.not_to have_json_path('spentHours') }

      it { is_expected.not_to have_json_path('overallCosts') }

      describe 'embedded' do
        it { is_expected.not_to have_json_path('_embedded/costObject') }

        it { is_expected.not_to have_json_path('_embedded/summarizedCostEntries') }
      end
    end

    describe '_links' do
      it { is_expected.not_to have_json_path('_links/log_costs') }
    end
  end

  describe '.to_eager_load' do
    it 'includes cost entries with dependencies' do
      expect(described_class.to_eager_load.any? { |el|
        el.is_a?(Hash) && el[:cost_entries] == [:project, :user]
      }).to be_truthy
    end

    it 'includes time entries with dependencies' do
      expect(described_class.to_eager_load.any? { |el|
        el.is_a?(Hash) && el[:time_entries] == [:project, :user]
      }).to be_truthy
    end

    it 'includes the cost objects' do
      expect(described_class.to_eager_load.any? { |el|
        el == :cost_object
      }).to be_truthy
    end
  end

  describe '#cache_key' do
    def joined_cache_key
      representer.cache_key.join('/')
    end

    before do
      allow(work_package.project)
        .to receive(:module_enabled?)
        .and_return false

      original_cache_key
    end

    let(:original_cache_key) { joined_cache_key }

    it 'changes depending on whether costs is enabled or not' do
      allow(work_package.project)
        .to receive(:module_enabled?)
        .with('costs_module')
        .and_return true

      expect(joined_cache_key).to_not eql(original_cache_key)
    end
  end
end
