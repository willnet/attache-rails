var gulp = require('gulp')
var eslint = require('gulp-eslint')
var source = require('vinyl-source-stream')
var connect = require('gulp-connect')
var babelify = require('babelify')
var browserify = require('browserify')

var config = {
  src: {
    dir: 'src/javascripts',
    mainjs: 'attache.js'
  },
  dest: {
    dir: 'app/assets/javascripts'
  }
}

gulp.task('lint', function () {
  return gulp.src([config.src.dir + '/**/*.js', 'gulpfile.js'])
    .pipe(eslint())
    .pipe(eslint.format())
    .pipe(eslint.failAfterError())
})

gulp.task('watch', function () {
  gulp.watch([config.src.dir + '/**/*.js', 'gulpfile.js'], ['js'])
  gulp.watch(['app/index.html'], connect.reload())
})

gulp.task('js', ['lint'], function (done) {
  return browserify({ entries: [config.src.dir + '/' + config.src.mainjs], debug: true })
    .transform(babelify)
    .bundle()
    .on('error', function () {
      console.error.apply(console, arguments)
      done()
    })
    .pipe(source(config.src.mainjs))
    .pipe(gulp.dest(config.dest.dir))
    .pipe(connect.reload())
})

gulp.task('connect', ['js', 'watch'], function () {
  connect.server({
    root: ['app'],
    port: 9005,
    base: 'http://localhost',
    livereload: true
  })
})

gulp.task('default', ['js', 'watch'])
