project('singularity-ledstudio', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-ledstudio"', language: 'c')
subdir('po')

gtk_dep = dependency('gtk4')
gee_dep = dependency('gee-0.8')
json_dep = dependency('json-glib-1.0')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

executable('singularity-ledstudio',
  files('src/app.vala', 'src/ribbon.vala', 'src/window.vala'),
  dependencies: [gtk_dep, gee_dep, json_dep, libsingularity_dep],
  install: true
)

install_data('data/dev.sinty.ledstudio.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/icons/dev.sinty.ledstudio.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
