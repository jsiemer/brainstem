require 'spec_helper'
require 'brainstem/dsl/association'

describe Brainstem::DSL::Association do
  let(:name) { :user }
  let(:target_class) { User }
  let(:description) { "This object's user" }
  let(:options) { { } }
  let(:association) { Brainstem::DSL::Association.new(name, target_class, description, options) }
  let(:context) { { } }

  describe "#run_on" do
    context 'with no special options' do
      it 'calls the method by name on the model' do
        object = Object.new
        mock(object).user
        association.run_on(object, context)
      end
    end

    context 'when given a via' do
      let(:options) { { via: :user2 } }

      it 'calls the method named in :via on the model' do
        object = Object.new
        mock(object).user2
        association.run_on(object, context)
      end
    end

    context 'when given a dynamic lambda' do
      let(:options) { { dynamic: lambda { |model| some_instance_method; :return_value } } }

      it 'calls the lambda in the context of the given instance' do
        instance = Object.new
        mock(instance).some_instance_method
        expect(association.run_on(:anything, context, instance)).to eq :return_value
      end
    end

    context 'when given a lookup lambda' do
      let(:model_id) { 23 }
      let(:options) { { lookup: lambda { |models| some_instance_method; Hash[models.map { |model| [model.id, model.username] }] } } }
      let(:first_model) { target_class.create(username: 'Ben') }
      let(:second_model) { target_class.create(username: 'Nate') }
      let(:context) {
        {
            lookup: Brainstem::Presenter.new.send(:empty_lookup_cache, [], [name.to_s]),
            models: [first_model, second_model]
        }
      }
      # context => {:lookup=>{:fields=>{}, :associations=>{'user'=>nil}}}

      context 'The first model is ran' do
        it 'builds lookup cache and returns the value' do
          expect(context[:lookup][:associations][name]).to eq(nil)
          instance = Object.new
          mock(instance).some_instance_method
          expect(association.run_on(first_model, context, instance)).to eq('Ben')
          expect(context[:lookup][:associations][name.to_s]).to eq({ first_model.id => 'Ben', second_model.id => 'Nate' })
        end
      end

      context 'The second model is ran after the first' do
        it 'returns the value from the lookup cache and does not run the lookup' do
          instance = Object.new
          mock(instance).some_instance_method
          association.run_on(first_model, context, instance)
          expect(context[:lookup][:associations][name.to_s]).to eq({ first_model.id => 'Ben', second_model.id => 'Nate' })

          mock(instance).some_instance_method.never
          expect(association.run_on(second_model, context, instance)).to eq('Nate')
        end
      end
    end
  end
end