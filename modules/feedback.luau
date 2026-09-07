--!nonstrict
return {
Name = "feedback", API = 1,
Requires = {},
Install = function(context)
	local DetectFeedbackEvasion = context.DetectFeedbackEvasion
	local HttpService = context.HttpService
	local NormalizeFeedbackText = context.NormalizeFeedbackText
	local NullUI = context.NullUI
	local SanitizeFeedbackText = context.SanitizeFeedbackText
local FEEDBACK_WEBHOOK_COOLDOWN = 30
local LastFeedbackWebhookAt = 0

function NullUI:SendFeedbackWebhook(webhookUrl, stars, message, opts)
	opts = opts or {}
	stars = math.clamp(math.floor((stars or 0) + 0.5), 0, 5)

	local now = os.clock()
	if now - LastFeedbackWebhookAt < FEEDBACK_WEBHOOK_COOLDOWN then
		self:Notify({
			Title = "Feedback",
			Text  = string.format(
				"Please wait %ds before sending more feedback.",
				math.ceil(FEEDBACK_WEBHOOK_COOLDOWN - (now - LastFeedbackWebhookAt))
			),
			Type  = "warning",
			Duration = 3,
		})
		return false
	end

	if not webhookUrl or webhookUrl == "" then
		self:Notify({
			Title = "Feedback",
			Text  = "No webhook configured.",
			Type  = "warning",
			Duration = 4,
		})
		return false
	end

	local httpRequest = (syn and syn.request) or http_request or request
	if not httpRequest then
		self:Notify({
			Title = "Feedback",
			Text  = "Your executor doesn't support HTTP requests.",
			Type  = "error",
			Duration = 4,
		})
		return false
	end

	local normalizedMessage = NormalizeFeedbackText(message or "")
	local hasEvasion = DetectFeedbackEvasion(normalizedMessage)
	local cleanMessage = SanitizeFeedbackText(message)

	if hasEvasion or cleanMessage:find("blocked") then
		LastFeedbackWebhookAt = now
		self:Notify({
			Title = "Blocked",
			Text = "Unallowed content detected.",
			Type = "error",
			Duration = 4,
		})
		return false
	end

	LastFeedbackWebhookAt = now

	local starDisplay = string.rep("\226\152\133", stars) .. string.rep("\226\152\134", 5 - stars)
	local embedColor = opts.Color or 0xFFC440
	local hasInvite = cleanMessage:find("%[invite removed%]") or cleanMessage:find("%[link removed%]")

	local body = HttpService:JSONEncode({
		allowed_mentions = { parse = {} },
		embeds = {{
			title = opts.Title or "New UI Feedback",
			description = starDisplay .. "  (" .. stars .. "/5)",
			color = embedColor,
			fields = {
				{ name = "Message", value = cleanMessage, inline = false },
			},
			footer = { text = hasInvite and "Invites removed" or "Submitted anonymously" },
			timestamp = DateTime.now():ToIsoDate(),
		}},
	})

	task.spawn(function()
		local ok, err = pcall(httpRequest, {
			Url = webhookUrl,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
		self:Notify({
			Title = ok and "Feedback Sent" or "Failed to Send",
			Text  = ok and "Thanks for rating the UI!" or tostring(err),
			Type  = ok and "success" or "error",
			Duration = 3,
		})
	end)

	return true
end


end,
}
