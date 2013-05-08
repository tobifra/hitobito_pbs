# encoding: UTF-8
require 'spec_helper'
require 'csv'

describe CsvImportsController do
  include CsvImportMacros
  let(:group) { groups(:top_group) }
  let(:person) { people(:top_leader) }
  before { sign_in(person) }


  describe "POST #define_mapping" do

    it "populates flash, data and columns" do
      file = Rack::Test::UploadedFile.new(path(:utf8), "text/csv")
      post :define_mapping, group_id: group.id, csv_import: { file: file }
      parser = assigns(:parser)
      parser.to_csv.should be_present
      parser.headers.should be_present
      flash[:notice].should =~ /1 Datensatz erfolgreich gelesen/
    end

    it "redisplays form if failed to parse csv" do
      file = Rack::Test::UploadedFile.new(path(:utf8,:ods),"text/csv")
      post :define_mapping, group_id: group.id, csv_import: { file: file }
      flash[:data].should_not be_present
      flash[:alert].should =~ /Fehler beim Lesen von utf8.ods/
      should redirect_to new_group_csv_imports_path(group)
    end

    it "renders form when submitted without file" do
      post :define_mapping, group_id: group.id
      should redirect_to new_group_csv_imports_path(group)
    end
  end

  describe "POST #create" do
    let(:data) { File.read(path(:utf8)) }
    let(:role_type) { "Group::TopGroup::Leader" }
    let(:mapping) { { Vorname: 'first_name', Nachname: 'last_name', Geburtsdatum: 'birthday' } }
    let(:required_params) { { group_id: group.id, data: data, role_type: role_type, csv_import: mapping } }

    it "redirects if role_type is missing" do
      post :create, group_id: group.id, data: data, csv_import: { first_name: 'first_name' }
      should redirect_to new_group_csv_imports_path(group)
    end


    it "renders define_mapping if button is pressed" do
      post :create, required_params.merge(button: '')
      should render_template(:define_mapping)
    end

    it "populates flash and redirects to group role list" do
      expect { post :create, required_params }.to change(Person,:count).by(1)
      flash[:notice].should eq ["1 Person (Leader) wurde erfolgreich importiert."]
      flash[:alert].should_not be_present
      should redirect_to group_people_path(group, role_types: role_type, name: "Leader")
    end

    context "mapping misses attribute" do
      let(:mapping) { { email: :email, role: role_type } }
      let(:data) { generate_csv(%w{name email}, %w{foo foo@bar.net}) }

      it "imports first person and displays errors for second person" do
        expect { post :create, required_params }.to change(Person,:count).by(0)
        flash[:alert].should eq ["1 Person (Leader) wurde nicht importiert.",
                                 "Zeile 1: Bitte geben Sie einen Namen ein"]
        should redirect_to group_people_path(group, role_types: role_type, name: "Leader")
      end
    end

    context "invalid phone number value" do
      let(:mapping) { { Vorname: 'first_name', Telefon: 'phone_number_vater', role: role_type } }
      let(:data) { generate_csv(%w{Vorname Telefon}, %w{foo }) }

      it "is ignored" do
        expect { post :create, required_params }.to change(Person,:count).by(1)
        flash[:alert].should be_blank
        should redirect_to group_people_path(group, role_types: role_type, name: "Leader")
      end
    end

    context "list" do
      let(:data) { File.read(path(:list)) }
      let(:last_person) { Person.last }

      context "mapping single attribute" do
        let(:mapping) { { first_name: 'first_name' } }

        it "imports first name of all 4 people" do
          expect { post :create, required_params }.to change(Person,:count).by(4)
          flash[:alert].should be_blank
          last_person.last_name.should be_blank
          last_person.first_name.should be_present
        end
      end

      context "mapping all attributes" do
        let(:mapping) { headers_mapping(CSV.parse(data, headers: true)) }

        it "imports single person" do
          expect { post :create, required_params }.to change(Person,:count).by(1)
          last_person.last_name.should be_present
          last_person.phone_numbers.should have(4).items
          last_person.social_accounts.should have(3).items
        end
      end
    end

    context "doublette handling" do
      context "multiple updates to single person" do
        let(:mapping) { { vorname: :first_name, email: :email, nickname: :nickname } }
        let(:data) { generate_csv(%w{vorname email nickname}, %w{foo foo@bar.net foobar}, %w{bar bar@bar.net barfoo}) }

        before do
          @person = Fabricate(:person, first_name: 'bar', email: 'foo@bar.net', nickname: '')
          @role_count = Role.count
          @person_count = Person.count
        end

        it "last update wins" do
          post :create, required_params

          Role.count.should eq @role_count + 1
          Person.count.should eq @person_count
          flash[:notice].should eq  ["1 Person (Leader) wurde erfolgreich aktualisiert."]
          @person.reload.nickname.should eq 'foobar'
        end
      end

      context "csv data matches multiple people" do
        let(:mapping) { { vorname: :first_name, email: :email, role: role_type } }
        let(:data) { generate_csv(%w{vorname email}, %w{foo foo@bar.net}) }

        it "reports error if multiple candidates for doublettes are found" do
          Fabricate(:person, first_name: 'bar', email: 'foo@bar.net')
          Fabricate(:person, first_name: 'foo', email: 'bar@bar.net')
          post :create, required_params
          flash[:alert].should eq ["1 Person (Leader) wurde nicht importiert.",
                                   "Zeile 1: 2 Treffer in Duplikatserkennung."]
        end
      end
    end
  end
end
