# encoding: utf-8
class CreateDefaultsAndAddChinese < ActiveRecord::Migration
  def up
    ChangeableObjectType.create_enumerated
    Activity.create_enumerated
    Language.reset_column_information
    Language.create_english # Ensure that we have our default language before inserting any...
    Language.create(iso_639_1: 'zh-Hant', iso_639_2: 'zh-Hant', iso_639_3: 'zh-Hant', source_form: '繁體中文', sort_order: 1,
                    activated_on: Time.now.utc, language_group_id: 1)
  end

  def down
    # Nothing to do.
  end
end
