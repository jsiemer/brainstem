require 'spec_helper'

describe Brainstem::QueryStrategies::FilterAndSearch do
  let(:bob) { User.find_by_username('bob') }

  let(:params) { {
    "owned_by" => bob.id.to_s,
    per_page: 7,
    page: 1,
    search: 'toot, otto, toot',
  } }

  let(:options) { {
    primary_presenter: CheesePresenter.new,
    table_name: 'cheeses',
    default_per_page: 20,
    default_max_per_page: 200,
    default_max_filter_and_search_page: 500,
    params: params
  } }

  describe '#execute' do
    before do
      CheesePresenter.search do |string, options|
        [[2,3,4,5,6,8,9,10,11,12], 11]
      end

      CheesePresenter.filter(:owned_by) { |scope, user_id| scope.owned_by(user_id.to_i) }
      CheesePresenter.sort_order(:id)   { |scope, direction| scope.order("cheeses.id #{direction}") }
    end

    it 'takes the intersection of the search and filter results' do
      results, count = described_class.new(options).execute(Cheese.unscoped)
      expect(count).to eq(8)
      expect(results.map(&:id)).to eq([2,3,4,5,8,10,11])
    end

    it "applies ordering to the scope" do
      options[:params]["order"] = 'id:desc'
      proxy.instance_of(Brainstem::Presenter).apply_ordering_to_scope(anything, anything).times(1)
      results, count = described_class.new(options).execute(Cheese.unscoped)
      expect(count).to eq(8)
      expect(results.map(&:id)).to eq([12,11,10,8,5,4,3])
    end
  end
end
