package app

import (
	"github.com/nhle/task-management/internal/model"
	"github.com/nhle/task-management/internal/source"
)

// taskToItemDetail converts a model.Task into a source.ItemDetail
// for display in the detail view. This is used when we only have
// the stored task and have not fetched extended detail from the source.
func taskToItemDetail(task *model.Task) *source.ItemDetail {
	return &source.ItemDetail{
		Task:         *task,
		RenderedBody: task.Description,
		Metadata:     make(map[string]string),
		Comments:     nil,
	}
}
