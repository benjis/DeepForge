# frozen_string_literal: true

require 'json'
require_relative 'shared'
require_relative '../../cache/tool_catalog_fingerprint'

module DeepForge
  module Loop
    class Pipeline
      class ToolCatalogManager
        include Shared

        def initialize(opts)
          @opts = opts
        end

        def call(context)
          thread_id = context[:thread_id]
          turn_id = context[:turn_id]
          thread = context[:thread]
          turn = context[:turn]
          model_capabilities = context[:model_capabilities]
          effective_mode = context[:effective_mode]
          skill_resolution = context[:skill_resolution]
          allowed_tool_names = context[:allowed_tool_names]

          tool_specs = @opts[:tool_host]&.list_tools(tool_context) || []
          context[:tool_specs] = tool_specs

          tool_provider_metadata = tool_specs.to_h do |tool|
            [tool[:name], { provider_id: tool[:provider_id], provider_kind: tool[:provider_kind] }]
          end
          context[:tool_provider_metadata] = tool_provider_metadata

          tool_catalog = ToolCatalogFingerprint.build(tool_specs)
          context[:tool_catalog] = tool_catalog

          tool_catalog_drift = record_tool_catalog_fingerprint(
            thread_id: thread_id,
            workspace: thread&.dig(:workspace) || '',
            mode: effective_mode || 'agent',
            model: model_capabilities[:id],
            active_skill_ids: skill_resolution[:active_skill_ids],
            allowed_tool_names: allowed_tool_names,
            fingerprint: tool_catalog[:fingerprint],
            tool_names: tool_catalog[:tool_names],
            tool_hashes: tool_catalog[:tool_hashes]
          )
          context[:tool_catalog_drift] = tool_catalog_drift

          if tool_catalog_drift[:kind] != :none
            drift_message = build_tool_catalog_drift_message(tool_catalog, tool_catalog_drift[:kind])
            record_tool_catalog_drift(
              thread_id: thread_id,
              turn_id: turn_id,
              fingerprint: tool_catalog[:fingerprint],
              tool_count: tool_catalog[:tool_count],
              tool_names: tool_catalog[:tool_names],
              change_kind: tool_catalog_drift[:kind],
              message: drift_message
            )
          end

          if turn
            @opts[:turns]&.update_turn_metadata(thread_id, turn_id, {
                                                  active_skill_ids: skill_resolution[:active_skill_ids],
                                                  skill_injection_bytes: skill_resolution[:injected_bytes],
                                                  injected_memory_ids: context[:memories]&.map(&:id),
                                                  tool_catalog_fingerprint: tool_catalog[:fingerprint],
                                                  tool_catalog_tool_count: tool_catalog[:tool_count],
                                                  tool_catalog_drift: tool_catalog_drift[:kind] != :none
                                                })
          end

          return :stop if tool_catalog_drift[:kind] == :breaking

          :continue
        end

        private

        def record_tool_catalog_fingerprint(input)
          key = JSON.generate({
                                threadId: input[:thread_id],
                                workspace: input[:workspace],
                                mode: input[:mode],
                                model: input[:model],
                                activeSkillIds: (input[:active_skill_ids] || []).sort,
                                allowedToolNames: (input[:allowed_tool_names] || []).sort
                              })

          current = {
            fingerprint: input[:fingerprint],
            tool_names: input[:tool_names],
            tool_hashes: input[:tool_hashes]
          }

          previous = @opts[:tool_catalog_snapshots]&.dig(key)
          @opts[:tool_catalog_snapshots]&.store(key, current)

          return { kind: :none } unless previous
          return { kind: :none } if previous[:fingerprint] == input[:fingerprint]

          additive = additive_tool_catalog_change?(previous, current)
          { kind: additive ? :additive : :breaking, previous: previous }
        end

        def additive_tool_catalog_change?(previous, current)
          added = current[:tool_names].any? { |name| !previous[:tool_hashes][name] }
          return false unless added

          previous[:tool_names].all? do |name|
            previous_hash = previous[:tool_hashes][name]
            current_hash = current[:tool_hashes][name]
            previous_hash && current_hash && previous_hash == current_hash
          end
        end

        def build_tool_catalog_drift_message(tool_catalog, change_kind)
          sample = tool_catalog[:tool_names].first(12).join(', ')
          suffix = tool_catalog[:tool_names].length > 12 ? ", +#{tool_catalog[:tool_names].length - 12} more" : ''
          policy = if change_kind == :additive
                     'Only additive tool changes are allowed in-place; DeepForge will continue with the refreshed tool list.'
                   else
                     'Non-additive tool changes can invalidate prompt-cache assumptions; DeepForge stopped this turn. Start a new thread after editing, removing, or reordering tool schemas.'
                   end
          parts = [
            "Tool catalog changed for this thread (#{tool_catalog[:tool_count]} tools, fingerprint #{tool_catalog[:fingerprint]}).",
            policy
          ]
          parts << "Current tools: #{sample}#{suffix}." unless sample.empty?
          parts.join(' ')
        end

        def record_tool_catalog_drift(thread_id:, turn_id:, fingerprint:, tool_count:, tool_names:, change_kind:,
                                      message:)
          @opts[:turns]&.apply_item(thread_id, make_error_item(
            "item_#{turn_id}_tool_catalog_changed_#{fingerprint}",
            thread_id,
            turn_id,
            message,
            'tool_catalog_changed'
          ))
          @opts[:events]&.record(
            kind: 'tool_catalog_changed',
            thread_id: thread_id,
            turn_id: turn_id,
            fingerprint: fingerprint,
            tool_count: tool_count,
            change_kind: change_kind,
            tool_names: tool_names.first(50),
            message: message
          )
        end
      end
    end
  end
end
