# encoding: utf-8

#  Copyright (c) 2019, Pfadibewegung Schweiz. This file is part of
#  hitobito_pbs and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_pbs.

module Pbs::Event::QualificationsController
  extend ActiveSupport::Concern

  included do
    alias_method_chain :update, :course_confirmation_flag
  end

  def has_confirmations
    params[:has_confirmations] == '1'
  end

  def update_with_course_confirmation_flag
    if current_ability.can?(:update, event)
      event.update_attributes(has_confirmations: has_confirmations)
    end
    update_without_course_confirmation_flag
  end

end
