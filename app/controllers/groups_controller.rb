class GroupsController < ApplicationController
  def index
    # currently also using this endpoint to pull down suggested groups
    groups = if params[:limit].present? # Get a specific amount of trending
      Group.trending(params[:limit].to_i)
    elsif params[:trending].present? # Get all trending groups, paginated
      Group.trending(0).page(params[:page]).per(20)
    elsif params[:user_id].present? # Get user groups
      User.find(params[:user_id]).groups.page(params[:page]).per(20)
    else # Get recent groups
      Group.order('created_at DESC').take(6)
    end

    respond_to do |format|
      format.json do
        render json: groups, meta: {cursor: 1 + (params[:page] || 1).to_i}
      end
      format.html do
        preload_to_ember! groups
        render_ember
      end
    end
  end

  def show
    group = Group.find(params[:id])

    respond_to do |format|
      format.json { render json: group }
      format.html do
        preload_to_ember! group
        render_ember
      end
    end
  end

  def new
    authenticate_user!
    render_ember
  end

  def create
    authenticate_user!

    group_hash = params.require(:group).permit(:name, :bio, :about).to_h

    # Remove this once out of beta
    return error! "Users are limited to one group during beta", 400 if Rails.env.production? && GroupMember.admin.where(user: current_user).count > 0
    return error! "Group with that name already exists", 409 if Group.exists?(['lower(name) = ?', group_hash['name'].downcase])
    group = Group.new_with_admin(group_hash, current_user)

    group.save!
    render json: group, status: :created
  end

  def update
    authenticate_user!
    group = Group.find(params[:id])
    group_hash = params.require(:group).permit(:bio, :about, :cover_image_url, :avatar_url).to_h

    if current_user.admin? || group.member(current_user).admin?
      # cleanup image uploads if they are bad
      group_hash['cover_image'] = group_hash.delete('cover_image_url')
      group_hash.delete('cover_image') unless group_hash['cover_image'] =~ /^data:image/
      group_hash['avatar'] = group_hash.delete('avatar_url')
      group_hash.delete('avatar') unless group_hash['avatar'] =~ /^data:image/


      group.attributes = group_hash
      group.save!
      render json: group
    else
      return error! "Only admins can edit the group", 403
    end
  end

  def destroy
    authenticate_user!

    # Only site admins should be able to delete
    # Sorry users, once you make a group it's part of the commons.
    if current_user.admin?
      group = Group.find(params[:id])
      group.delay.destroy
      render json: {}
    else
      return error! "Only Hummingbird administrators can delete groups", 403
    end
  end
end
